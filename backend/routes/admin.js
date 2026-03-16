const express    = require('express');
const Attendance = require('../models/attendance');

const router   = express.Router();
const User     = require('../models/user');
const Customer = require('../models/customer');
const Job      = require('../models/job');
const Config   = require('../models/config');
const bcrypt   = require('bcryptjs');
const jwt      = require('jsonwebtoken');

// Returns current date in IST (UTC+5:30) as YYYY-MM-DD
function todayIST() {
  const now = new Date();
  const ist = new Date(now.getTime() + 5.5 * 60 * 60 * 1000);
  return ist.toISOString().split('T')[0];
}

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

const axios = require('axios');

// Extract lat/lng from any Google Maps URL (short or full)
// Ported from old app — proven working
async function extractLatLng(url) {
  try {
    if (!url) return null;

    // Step 0: Direct ?q=lat,lng pattern
    const directMatch = url.match(/q=(-?\d+\.\d+),(-?\d+\.\d+)/);
    if (directMatch) {
      return { lat: parseFloat(directMatch[1]), lng: parseFloat(directMatch[2]) };
    }

    // Step 1: Expand shortened URLs (maps.app.goo.gl / goo.gl/maps)
    if (/maps\.app\.goo\.gl|goo\.gl\/maps/.test(url)) {
      try {
        const response = await axios.get(url, {
          maxRedirects: 0,
          validateStatus: s => s === 301 || s === 302,
        });
        url = response.headers.location || url;
      } catch (e) {
        console.warn('[extractLatLng] Could not expand short URL:', e.message);
      }
    }

    // Step 2: Multiple coordinate patterns on expanded URL
    const patterns = [
      /@(-?\d+\.\d+),(-?\d+\.\d+)/,
      /!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)/,
      /center=(-?\d+\.\d+),(-?\d+\.\d+)/,
      /destination=(-?\d+\.\d+),(-?\d+\.\d+)/,
      /%2C(-?\d+\.\d+)%2C(-?\d+\.\d+)/,
      /[?&]q=(-?\d+\.\d+),(-?\d+\.\d+)/,
      /ll=(-?\d+\.\d+),(-?\d+\.\d+)/,
      /place\/(-?\d+\.\d+),(-?\d+\.\d+)/,
    ];
    for (const regex of patterns) {
      const match = url.match(regex);
      if (match) {
        return { lat: parseFloat(match[1]), lng: parseFloat(match[2]) };
      }
    }

    console.log('[extractLatLng] Could not extract coords from:', url);
    return null;
  } catch (err) {
    console.error('[extractLatLng] Error:', err.message);
    return null;
  }
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
    const today     = todayIST();
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
    const today     = todayIST();
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
    const today = todayIST();
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
      const coords = await extractLatLng(homeMapsLink);
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
    const location = await extractLatLng(mapsLink);
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
    const { search } = req.query;
    const filter = search
      ? { customerName: { $regex: search, $options: 'i' } }
      : {};
    const customers = await Customer.find(filter).sort({ createdAt: -1 });
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
      updates.location = await extractLatLng(mapsLink) || { lat: null, lng: null };
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
    const today    = assignedDate || todayIST();
    const existing = await Job.findOne({
      customerId, assignedDate: today, status: { $nin: ['Cancelled'] },
    });
    if (existing) return res.status(400).send("Customer already assigned today");

    // sortOrder = next in line for this employee on this date
    const lastJob = await Job.findOne({ employeeId, assignedDate: today })
      .sort({ sortOrder: -1 });
    const sortOrder = lastJob ? lastJob.sortOrder + 1 : 1;

    const job      = await Job.create({ customerId, employeeId, serviceType, assignedDate: today, status: 'Pending', sortOrder });
    const populated= await Job.findById(job._id).populate('customerId');
    res.json(populated);
  } catch (err) { res.status(500).send("Server error"); }
});

// GET /admin/planner/:employeeId?date=YYYY-MM-DD — jobs for employee on date
router.get('/planner/:employeeId', adminAuth, async (req, res) => {
  try {
    const date = req.query.date || todayIST();
    const jobs = await Job.find({
      employeeId:   req.params.employeeId,
      assignedDate: date,
    }).populate('customerId').sort({ sortOrder: 1 });
    res.json(jobs);
  } catch (err) { res.status(500).send("Server error"); }
});

// PUT /admin/planner/reorder — reorder jobs for employee on date
// Body: { employeeId, date, jobIds: ['id1','id2',...] } — ordered array
router.put('/planner/reorder', adminAuth, async (req, res) => {
  try {
    const { jobIds } = req.body;
    if (!Array.isArray(jobIds)) return res.status(400).send("jobIds array required");
    await Promise.all(
      jobIds.map((id, index) =>
        Job.findByIdAndUpdate(id, { sortOrder: index + 1 })
      )
    );
    res.json({ success: true });
  } catch (err) { res.status(500).send("Server error"); }
});

// DELETE /admin/planner/:jobId — remove a planned job (only if Pending)
router.delete('/planner/:jobId', adminAuth, async (req, res) => {
  try {
    const job = await Job.findById(req.params.jobId);
    if (!job) return res.status(404).send("Job not found");
    if (job.status !== 'Pending') return res.status(400).send("Can only remove pending jobs");
    await Job.findByIdAndDelete(req.params.jobId);
    res.json({ success: true });
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

    // Helper: is this job payable (no unresolved complaint)
    const isPayable = (job) =>
      !job.complaint?.raised || job.complaint?.resolved === true;

    // Group by date (IST) — only payable jobs count for distance
    const byDate = {};
    for (const job of jobs) {
      const ist = new Date(job.completedAt.getTime() + 5.5 * 60 * 60 * 1000);
      const dk  = ist.toISOString().split('T')[0];
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
        const customer  = job.customerId;
        const carType   = customer?.carType || 'Hatchback';
        const svcType   = job.serviceType   || '';
        const payable   = isPayable(job);
        let earnings    = 0;
        if (payable) {
          if (svcType === 'Exterior') {
            earnings = pricing.exterior?.[carType] ?? 20;
          } else if (svcType === 'Interior Standard') {
            earnings = pricing.interiorStandard ?? 40;
          } else if (svcType === 'Interior Premium') {
            earnings = pricing.interiorPremium ?? 60;
          }
          if (carTypeCounts[carType] !== undefined) carTypeCounts[carType]++;
          totalJobEarnings += earnings;
        }
        jobDetails.push({
          jobId:         job._id,
          date,
          customerName:  customer?.customerName || '',
          carType,
          carModel:      customer?.carModel     || '',
          vehicleNo:     customer?.vehicleNumber || '',
          serviceType:   job.serviceType,
          serviceCount:  job.serviceCount,
          status:        job.status,
          earnings,
          cancelPhotoUrl: job.cancelPhotoUrl || null,
          cancelReason:   job.cancelReason   || null,
          cancelledAt:    job.cancelledAt    || null,
          complaint: job.complaint?.raised ? {
            raised:    job.complaint.raised,
            resolved:  job.complaint.resolved,
            reason:    job.complaint.reason,
            note:      job.complaint.note,
            raisedAt:  job.complaint.raisedAt,
          } : null,
        });
      }

      // Daily distance — sort by sortOrder, include cancelled jobs
      if (home) {
        const eligibleJobs = dayJobs
          .filter(job => {
            const payable = isPayable(job);
            // Completed payable jobs + all cancelled jobs count for distance
            return (job.status === 'Completed' && payable) ||
                    job.status === 'Cancelled';
          })
          .sort((a, b) => (a.sortOrder || 0) - (b.sortOrder || 0));

        const waypoints = [];
        for (const job of eligibleJobs) {
          const customer = job.customerId;
          let coords = null;
          if (customer?.location?.lat) {
            coords = { lat: customer.location.lat, lng: customer.location.lng };
          } else if (customer?.mapsLink) {
            coords = await extractLatLng(customer.mapsLink);
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

    const complainedJobs  = jobs.filter(j => j.complaint?.raised && !j.complaint?.resolved);
    const resolvedJobs    = jobs.filter(j => j.complaint?.raised &&  j.complaint?.resolved);

    res.json({
      employee: { id: employee._id, name: employee.name, email: employee.email,
                  hasHomeLocation: !!home },
      month, year, pricing,
      summary: {
        totalJobs:            jobs.length,
        complainedJobs:       complainedJobs.length,
        resolvedComplaints:   resolvedJobs.length,
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
// COMPLAINTS
// ═══════════════════════════════════════════════════════════════════════════

// POST /admin/complaints/:jobId — raise complaint
router.post('/complaints/:jobId', adminAuth, async (req, res) => {
  try {
    const { reason, note } = req.body;
    if (!reason) return res.status(400).send("reason required");

    const job = await Job.findById(req.params.jobId);
    if (!job) return res.status(404).send("Job not found");
    if (job.status !== 'Completed') return res.status(400).send("Can only complain on completed jobs");
    if (job.complaint?.raised && !job.complaint?.resolved)
      return res.status(400).send("Complaint already raised");

    // Decrement serviceCount on customer
    await Customer.findByIdAndUpdate(job.customerId,
      { $inc: { serviceCount: -1 } });

    const updated = await Job.findByIdAndUpdate(
      req.params.jobId,
      {
        'complaint.raised':   true,
        'complaint.reason':   reason,
        'complaint.note':     note || null,
        'complaint.raisedAt': new Date(),
        'complaint.resolved': false,
        'complaint.resolvedAt': null,
      },
      { new: true }
    ).populate('customerId');

    res.json(updated);
  } catch (err) { res.status(500).send("Server error"); }
});

// PUT /admin/complaints/:jobId/resolve — resolve complaint
router.put('/complaints/:jobId/resolve', adminAuth, async (req, res) => {
  try {
    const job = await Job.findById(req.params.jobId);
    if (!job) return res.status(404).send("Job not found");
    if (!job.complaint?.raised) return res.status(400).send("No complaint raised");
    if (job.complaint?.resolved) return res.status(400).send("Already resolved");

    // Restore serviceCount on customer
    await Customer.findByIdAndUpdate(job.customerId,
      { $inc: { serviceCount: 1 } });

    const updated = await Job.findByIdAndUpdate(
      req.params.jobId,
      {
        'complaint.resolved':   true,
        'complaint.resolvedAt': new Date(),
      },
      { new: true }
    ).populate('customerId');

    res.json(updated);
  } catch (err) { res.status(500).send("Server error"); }
});

// GET /admin/employees/:id/complaints — complaint summary for employee
router.get('/employees/:id/complaints', adminAuth, async (req, res) => {
  try {
    const month = parseInt(req.query.month) || new Date().getMonth() + 1;
    const year  = parseInt(req.query.year)  || new Date().getFullYear();
    const from  = new Date(year, month - 1, 1);
    const to    = new Date(year, month, 1);

    const jobs = await Job.find({
      employeeId:            req.params.id,
      'complaint.raised':    true,
      'complaint.raisedAt':  { $gte: from, $lt: to },
    }).populate('customerId', 'customerName carType');

    const result = jobs.map(j => ({
      jobId:        j._id,
      date:         j.completedAt
                      ? new Date(j.completedAt.getTime() + 5.5*60*60*1000).toISOString().split('T')[0]
                      : null,
      customerName: j.customerId?.customerName || '',
      carType:      j.customerId?.carType      || '',
      serviceType:  j.serviceType,
      reason:       j.complaint.reason,
      note:         j.complaint.note,
      raisedAt:     j.complaint.raisedAt,
      resolved:     j.complaint.resolved,
      resolvedAt:   j.complaint.resolvedAt,
    }));

    res.json({ total: result.length, resolved: result.filter(r => r.resolved).length, complaints: result });
  } catch (err) { res.status(500).send("Server error"); }
});


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

// ═══════════════════════════════════════════════════════════════════════════
// ATTENDANCE
// ═══════════════════════════════════════════════════════════════════════════

// GET /admin/attendance/:employeeId?date=YYYY-MM-DD
// Returns attendance record + towelSoakUrl from first completed/in-progress job that day
router.get('/attendance/:employeeId', adminAuth, async (req, res) => {
  try {
    const date   = req.query.date || todayIST();
    console.log(`[attendance] GET employeeId=${req.params.employeeId} date=${date}`);

    const record = await Attendance.findOne({
      employeeId: req.params.employeeId, date,
    });
    console.log(`[attendance] record found:`, record ? 'yes' : 'no',
      record ? `selfie=${!!record.selfieUrl} towels=${record.towelUrls.length}` : '');

    // Find towelSoak from first job that has one on this date
    const jobWithSoak = await Job.findOne({
      employeeId:          req.params.employeeId,
      assignedDate:        date,
      'images.towelSoak':  { $ne: null },
    });

    const response = record
      ? record.toObject()
      : { selfieUrl: null, towelUrls: [], date,
          selfieApproval: 'pending', towelsApproval: 'pending', towelSoakApproval: 'pending' };

    response.towelSoakUrl  = jobWithSoak?.images?.towelSoak || null;
    response.towelSoakJobId = jobWithSoak?._id?.toString() || null;

    res.json(response);
  } catch (err) { console.error(err); res.status(500).send("Server error"); }
});

// PATCH /admin/attendance/:employeeId/approve?date=YYYY-MM-DD
// body: { type: 'selfie'|'towels'|'towelSoak', status: 'approved'|'rejected' }
router.patch('/attendance/:employeeId/approve', adminAuth, async (req, res) => {
  try {
    const date   = req.query.date || todayIST();
    const { type, status } = req.body;

    const fieldMap = {
      selfie:    'selfieApproval',
      towels:    'towelsApproval',
      towelSoak: 'towelSoakApproval',
    };
    const field = fieldMap[type];
    if (!field) return res.status(400).send("Invalid type");
    if (!['approved', 'rejected'].includes(status))
      return res.status(400).send("Invalid status");

    const record = await Attendance.findOneAndUpdate(
      { employeeId: req.params.employeeId, date },
      { $set: { [field]: status } },
      { upsert: true, new: true }
    );
    res.json(record);
  } catch (err) { console.error(err); res.status(500).send("Server error"); }
});

module.exports = router;