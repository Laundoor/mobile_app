const express  = require('express');
const router   = express.Router();
const User     = require('../models/user');
const Customer = require('../models/customer');
const Job      = require('../models/job');
const Config   = require('../models/config');
const bcrypt   = require('bcryptjs');
const jwt      = require('jsonwebtoken');

// ── MIDDLEWARE ────────────────────────────────────────────────────────────────
function adminAuth(req, res, next) {
  const header = req.headers['authorization'];
  if (!header) return res.status(401).send("No token");
  const token = header.split(' ')[1];
  try {
    const decoded = jwt.verify(token, "secretkey");
    if (decoded.role !== 'admin') return res.status(403).send("Admins only");
    req.adminId = decoded.id;
    next();
  } catch {
    res.status(401).send("Invalid token");
  }
}

// Extract lat/lng from Google Maps link
function extractLatLng(mapsLink) {
  if (!mapsLink) return null;
  const patterns = [
    /@(-?\d+\.\d+),(-?\d+\.\d+)/,
    /[?&]q=(-?\d+\.\d+),(-?\d+\.\d+)/,
    /ll=(-?\d+\.\d+),(-?\d+\.\d+)/,
    /!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)/,
    /place\/(-?\d+\.\d+),(-?\d+\.\d+)/,
  ];
  for (const p of patterns) {
    const m = mapsLink.match(p);
    if (m) return { lat: parseFloat(m[1]), lng: parseFloat(m[2]) };
  }
  return null;
}

// Haversine distance in KM
function haversineKm(lat1, lng1, lat2, lng2) {
  const R    = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a    = Math.sin(dLat/2)**2 +
               Math.cos(lat1*Math.PI/180) * Math.cos(lat2*Math.PI/180) *
               Math.sin(dLng/2)**2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
}

const DEFAULT_PRICING = {
  exterior: { Hatchback: 20, Sedan: 25, SUV: 30 },
  interiorStandard: 40,
  interiorPremium:  60,
  distancePerKm:    2,
};

// ═══════════════════════════════════════════════════════════════════════════
// DASHBOARD
// ═══════════════════════════════════════════════════════════════════════════
router.get('/dashboard', adminAuth, async (req, res) => {
  try {
    const today     = new Date().toISOString().split('T')[0];
    const employees = await User.find({ role: 'employee' }).select('-password');
    const allJobs   = await Job.find({ assignedDate: today });
    const data = employees.map(emp => {
      const empJobs       = allJobs.filter(j => j.employeeId.toString() === emp._id.toString());
      const isActiveToday = emp.lastActiveDate === today && emp.isActive;
      return {
        _id:        emp._id,
        name:       emp.name,
        email:      emp.email,
        isActive:   isActiveToday,
        totalToday: empJobs.length,
        pending:    empJobs.filter(j => j.status === 'Pending').length,
        inProgress: empJobs.filter(j => j.status === 'In Progress').length,
        completed:  empJobs.filter(j => j.status === 'Completed').length,
        cancelled:  empJobs.filter(j => j.status === 'Cancelled').length,
      };
    });
    res.json(data);
  } catch (err) { res.status(500).send("Server error"); }
});

// ═══════════════════════════════════════════════════════════════════════════
// EMPLOYEE MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════
router.post('/employees', adminAuth, async (req, res) => {
  try {
    const { name, email, password } = req.body;
    if (!name || !email || !password)
      return res.status(400).send("name, email, password required");
    const existing = await User.findOne({ email });
    if (existing) return res.status(400).send("Email already exists");
    const hashed = await bcrypt.hash(password, 10);
    const user   = await User.create({ name, email, password: hashed, role: 'employee' });
    res.json(user);
  } catch (err) { res.status(500).send("Server error"); }
});

router.get('/employees', adminAuth, async (req, res) => {
  try {
    const today     = new Date().toISOString().split('T')[0];
    const employees = await User.find({ role: 'employee' }).select('-password');
    const allJobs   = await Job.find({ assignedDate: today });
    const result = employees.map(emp => {
      const empJobs       = allJobs.filter(j => j.employeeId.toString() === emp._id.toString());
      const isActiveToday = emp.lastActiveDate === today && emp.isActive;
      return {
        ...emp.toObject(),
        isActive:      isActiveToday,
        todayJobs:     empJobs.length,
        pendingJobs:   empJobs.filter(j => j.status === 'Pending').length,
        inProgressJobs:empJobs.filter(j => j.status === 'In Progress').length,
        completedJobs: empJobs.filter(j => j.status === 'Completed').length,
      };
    });
    res.json(result);
  } catch (err) { res.status(500).send("Server error"); }
});

router.get('/employees/:id', adminAuth, async (req, res) => {
  try {
    const emp = await User.findById(req.params.id).select('-password');
    if (!emp) return res.status(404).send("Employee not found");
    const today = new Date().toISOString().split('T')[0];
    const jobs  = await Job.find({
      employeeId: req.params.id, assignedDate: today,
    }).populate('customerId');
    res.json({ employee: emp, jobs });
  } catch (err) { res.status(500).send("Server error"); }
});

// PUT /admin/employees/:id — update employee including home location
router.put('/employees/:id', adminAuth, async (req, res) => {
  try {
    const { homeMapsLink, ...rest } = req.body;
    const updates = { ...rest };
    if (homeMapsLink !== undefined) {
      const coords = extractLatLng(homeMapsLink);
      updates.homeMapsLink  = homeMapsLink || null;
      updates.homeLocation  = coords || { lat: null, lng: null };
    }
    const emp = await User.findByIdAndUpdate(
      req.params.id, updates, { new: true }).select('-password');
    res.json(emp);
  } catch (err) { res.status(500).send("Server error"); }
});

router.delete('/employees/:id', adminAuth, async (req, res) => {
  try {
    await User.findByIdAndDelete(req.params.id);
    res.send("Deleted");
  } catch (err) { res.status(500).send("Server error"); }
});

// ═══════════════════════════════════════════════════════════════════════════
// CUSTOMER MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════
router.post('/customers', adminAuth, async (req, res) => {
  try {
    const { customerName, address, vehicleNumber, vehicleColor,
            carModel, carType, phone, mapsLink } = req.body;
    if (!customerName) return res.status(400).send("customerName required");
    const location = extractLatLng(mapsLink);
    const customer = await Customer.create({
      customerName, address, vehicleNumber, vehicleColor,
      carModel, carType, phone,
      mapsLink: mapsLink || null,
      location: location || { lat: null, lng: null },
    });
    res.json(customer);
  } catch (err) { res.status(500).send("Server error"); }
});

router.get('/customers', adminAuth, async (req, res) => {
  try {
    const customers = await Customer.find().sort({ createdAt: -1 });
    res.json(customers);
  } catch (err) { res.status(500).send("Server error"); }
});

router.get('/customers/:id', adminAuth, async (req, res) => {
  try {
    const customer = await Customer.findById(req.params.id);
    if (!customer) return res.status(404).send("Not found");
    res.json(customer);
  } catch (err) { res.status(500).send("Server error"); }
});

router.get('/customers/:id/history', adminAuth, async (req, res) => {
  try {
    const jobs = await Job.find({ customerId: req.params.id })
      .sort({ createdAt: -1 })
      .populate('employeeId', 'name email');
    res.json(jobs);
  } catch (err) { res.status(500).send("Server error"); }
});

router.put('/customers/:id', adminAuth, async (req, res) => {
  try {
    const { mapsLink } = req.body;
    const updates = { ...req.body };
    if (mapsLink !== undefined) {
      updates.location = extractLatLng(mapsLink) || { lat: null, lng: null };
    }
    const customer = await Customer.findByIdAndUpdate(
      req.params.id, updates, { new: true });
    res.json(customer);
  } catch (err) { res.status(500).send("Server error"); }
});

router.delete('/customers/:id', adminAuth, async (req, res) => {
  try {
    await Customer.findByIdAndDelete(req.params.id);
    res.send("Deleted");
  } catch (err) { res.status(500).send("Server error"); }
});

// ═══════════════════════════════════════════════════════════════════════════
// JOB ASSIGNMENT
// ═══════════════════════════════════════════════════════════════════════════
router.post('/assign', adminAuth, async (req, res) => {
  try {
    const { customerId, employeeId, serviceType, assignedDate } = req.body;
    if (!customerId || !employeeId || !serviceType)
      return res.status(400).send("customerId, employeeId, serviceType required");
    const today    = assignedDate || new Date().toISOString().split('T')[0];
    const existing = await Job.findOne({
      customerId, assignedDate: today, status: { $nin: ['Cancelled'] },
    });
    if (existing) return res.status(400).send("Customer already assigned today");
    const job      = await Job.create({ customerId, employeeId, serviceType, assignedDate: today, status: 'Pending' });
    const populated= await Job.findById(job._id).populate('customerId');
    res.json(populated);
  } catch (err) { res.status(500).send("Server error"); }
});

router.put('/reassign', adminAuth, async (req, res) => {
  try {
    const { jobId, newEmployeeId } = req.body;
    if (!jobId || !newEmployeeId) return res.status(400).send("jobId and newEmployeeId required");
    const job = await Job.findByIdAndUpdate(
      jobId, { employeeId: newEmployeeId, status: 'Pending' }, { new: true }
    ).populate('customerId');
    res.json(job);
  } catch (err) { res.status(500).send("Server error"); }
});

// ═══════════════════════════════════════════════════════════════════════════
// CONFIG — PRICING
// ═══════════════════════════════════════════════════════════════════════════
router.get('/config/pricing', adminAuth, async (req, res) => {
  try {
    const doc = await Config.findOne({ key: 'pricing' });
    res.json(doc ? doc.value : DEFAULT_PRICING);
  } catch (err) { res.status(500).send("Server error"); }
});

router.put('/config/pricing', adminAuth, async (req, res) => {
  try {
    const updated = await Config.findOneAndUpdate(
      { key: 'pricing' },
      { key: 'pricing', value: req.body },
      { upsert: true, new: true }
    );
    res.json({ success: true, value: updated.value });
  } catch (err) { res.status(500).send("Server error"); }
});

// ═══════════════════════════════════════════════════════════════════════════
// SALARY
// ═══════════════════════════════════════════════════════════════════════════
router.get('/salary/:employeeId', adminAuth, async (req, res) => {
  try {
    const { employeeId } = req.params;
    const month = parseInt(req.query.month) || new Date().getMonth() + 1;
    const year  = parseInt(req.query.year)  || new Date().getFullYear();

    const from = new Date(year, month - 1, 1);
    const to   = new Date(year, month, 1);

    const employee = await User.findById(employeeId).select('-password');
    if (!employee) return res.status(404).json({ error: 'Employee not found' });

    const configDoc = await Config.findOne({ key: 'pricing' });
    const pricing   = configDoc ? configDoc.value : DEFAULT_PRICING;

    const jobs = await Job.find({
      employeeId,
      status:      'Completed',
      completedAt: { $gte: from, $lt: to },
    }).populate('customerId', 'customerName carType carModel vehicleNumber mapsLink location');

    // Group by date
    const byDate = {};
    for (const job of jobs) {
      const dk = job.completedAt.toISOString().split('T')[0];
      if (!byDate[dk]) byDate[dk] = [];
      byDate[dk].push(job);
    }

    const jobDetails    = [];
    const carTypeCounts = { Hatchback: 0, Sedan: 0, SUV: 0 };
    let totalJobEarnings      = 0;
    let totalDistanceKm       = 0;
    let totalDistanceEarnings = 0;

    const home = employee.homeLocation?.lat ? employee.homeLocation : null;

    for (const [date, dayJobs] of Object.entries(byDate).sort()) {
      for (const job of dayJobs) {
        const customer = job.customerId;
        const carType  = customer?.carType || 'Hatchback';
        const svcType  = job.serviceType   || '';
        let earnings   = 0;
        if (svcType === 'Exterior') {
          earnings = pricing.exterior?.[carType] ?? 20;
        } else if (svcType === 'Interior Standard') {
          earnings = pricing.interiorStandard ?? 40;
        } else if (svcType === 'Interior Premium') {
          earnings = pricing.interiorPremium ?? 60;
        }
        if (carTypeCounts[carType] !== undefined) carTypeCounts[carType]++;
        totalJobEarnings += earnings;
        jobDetails.push({
          jobId:        job._id,
          date,
          customerName: customer?.customerName || '',
          carType,
          carModel:     customer?.carModel     || '',
          vehicleNo:    customer?.vehicleNumber || '',
          serviceType:  job.serviceType,
          serviceCount: job.serviceCount,
          earnings,
        });
      }

      // Daily distance calculation
      if (home) {
        const waypoints = [];
        for (const job of dayJobs) {
          const customer = job.customerId;
          let coords = null;
          if (customer?.location?.lat) {
            coords = { lat: customer.location.lat, lng: customer.location.lng };
          } else if (customer?.mapsLink) {
            coords = extractLatLng(customer.mapsLink);
          }
          if (coords) waypoints.push(coords);
        }
        if (waypoints.length > 0) {
          let dayKm = 0;
          let prev  = home;
          for (const wp of waypoints) {
            dayKm += haversineKm(prev.lat, prev.lng, wp.lat, wp.lng);
            prev   = wp;
          }
          dayKm += haversineKm(prev.lat, prev.lng, home.lat, home.lng);
          totalDistanceKm       += dayKm;
          totalDistanceEarnings += dayKm * (pricing.distancePerKm ?? 2);
        }
      }
    }

    res.json({
      employee: { id: employee._id, name: employee.name, email: employee.email,
                  hasHomeLocation: !!home },
      month, year, pricing,
      summary: {
        totalJobs:            jobs.length,
        carTypeCounts,
        totalJobEarnings:     parseFloat(totalJobEarnings.toFixed(2)),
        totalDistanceKm:      parseFloat(totalDistanceKm.toFixed(2)),
        totalDistanceEarnings:parseFloat(totalDistanceEarnings.toFixed(2)),
        grandTotal:           parseFloat((totalJobEarnings + totalDistanceEarnings).toFixed(2)),
      },
      jobDetails,
    });
  } catch (err) {
    console.error('[Salary]', err);
    res.status(500).send("Server error");
  }
});

// ═══════════════════════════════════════════════════════════════════════════
// SEED
// ═══════════════════════════════════════════════════════════════════════════
router.post('/seed', async (req, res) => {
  try {
    const { name, email, password, secretKey } = req.body;
    if (secretKey !== 'LAUNDOOR_ADMIN_SEED') return res.status(403).send("Wrong secret key");
    const existing = await User.findOne({ email });
    if (existing) return res.status(400).send("Email already exists");
    const hashed = await bcrypt.hash(password, 10);
    const admin  = await User.create({ name, email, password: hashed, role: 'admin' });
    res.json(admin);
  } catch (err) { res.status(500).send("Server error"); }
});

module.exports = router;