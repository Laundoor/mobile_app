const express    = require('express');
const mongoose   = require('mongoose');
const Attendance = require('../models/attendance');
const Expense    = require('../models/expense');
const Fund       = require('../models/fund');

const router   = express.Router();
const User     = require('../models/user');
const Customer = require('../models/customer');
const Job      = require('../models/job');
const Config   = require('../models/config');
const { Invoice, getNextInvoiceNumber } = require('../models/invoice');
const SalarySlip = require('../models/salary_slip');
const bcrypt   = require('bcryptjs');
const jwt      = require('jsonwebtoken');
const axios    = require('axios');

// Extract lat/lng from any Google Maps URL (short or full)
async function extractLatLng(url) {
  try {
    if (!url) return null;

    // Step 0: Direct ?q=lat,lng pattern
    const directMatch = url.match(/q=(-?\d+\.\d+),(-?\d+\.\d+)/);
    if (directMatch)
      return { lat: parseFloat(directMatch[1]), lng: parseFloat(directMatch[2]) };

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
      if (match)
        return { lat: parseFloat(match[1]), lng: parseFloat(match[2]) };
    }

    console.log('[extractLatLng] Could not extract coords from:', url);
    return null;
  } catch (err) {
    console.error('[extractLatLng] Error:', err.message);
    return null;
  }
}

// Returns current date in IST (UTC+5:30) as YYYY-MM-DD
function todayIST() {
  const now = new Date();
  const ist = new Date(now.getTime() + 5.5 * 60 * 60 * 1000);
  return ist.toISOString().split('T')[0];
}

// Half-down rounding: rounds up only if fraction is strictly > 0.5
// e.g. 28.5 → 28, 28.51 → 29, 28.4 → 28, 28.9 → 29
function halfDownRound(value) {
  return Math.max(0, Math.ceil(value - 0.5));
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

// Haversine distance in KM — used as fallback
function haversineKm(lat1, lng1, lat2, lng2) {
  const R    = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a    = Math.sin(dLat/2)**2 +
               Math.cos(lat1*Math.PI/180) * Math.cos(lat2*Math.PI/180) *
               Math.sin(dLng/2)**2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
}

// Compute total route distance for one day using Google Distance Matrix API
// Points = [home, C1, C2, ..., Cn, home] — batched in ONE API call
// Falls back to haversine if API unavailable
async function computeDayDistanceKm(points) {
  if (points.length < 2) return 0;

  const apiKey = process.env.LOCATION_KEY;

  // Build consecutive leg pairs: [home→C1, C1→C2, ..., Cn→home]
  const origins      = points.slice(0, -1);
  const destinations = points.slice(1);

  // Google Distance Matrix allows max 25 origins and 25 destinations
  // For a normal day (≤24 stops) this is always one call
  if (apiKey && origins.length <= 25) {
    try {
      const origStr = origins.map(p => `${p.lat},${p.lng}`).join('|');
      const destStr = destinations.map(p => `${p.lat},${p.lng}`).join('|');
      const url = `https://maps.googleapis.com/maps/api/distancematrix/json` +
                  `?origins=${origStr}` +
                  `&destinations=${destStr}` +
                  `&mode=driving` +
                  `&units=metric` +
                  `&key=${apiKey}`;

      const { data } = await axios.get(url, { timeout: 10000 });

      if (data?.status === 'OK') {
        let totalKm = 0;
        let allOk   = true;
        for (let i = 0; i < origins.length; i++) {
          const element = data.rows?.[i]?.elements?.[i];
          if (element?.status === 'OK') {
            totalKm += element.distance.value / 1000;
          } else {
            // This leg failed — fall back to haversine for this leg only
            console.warn(`[distance] Leg ${i} fallback:`, element?.status);
            totalKm += haversineKm(
              origins[i].lat, origins[i].lng,
              destinations[i].lat, destinations[i].lng
            );
            allOk = false;
          }
        }
        if (!allOk) console.warn('[distance] Some legs used haversine fallback');
        return parseFloat(totalKm.toFixed(2));
      } else {
        console.error('[distance] Matrix API error:', data?.status, data?.error_message);
      }
    } catch (err) {
      console.error('[distance] Matrix API request failed:', err.message);
    }
  } else if (!apiKey) {
    console.warn('[distance] No LOCATION_KEY — using haversine fallback');
  }

  // Full haversine fallback for entire day
  let totalKm = 0;
  for (let i = 0; i < origins.length; i++) {
    totalKm += haversineKm(
      origins[i].lat, origins[i].lng,
      destinations[i].lat, destinations[i].lng
    );
  }
  return parseFloat(totalKm.toFixed(2));
}

const DEFAULT_PRICING = {
  exterior: { Hatchback: 20, Sedan: 25, SUV: 30 },
  interiorStandard: 40,
  interiorPremium:  60,
  distancePerKm:    2,
  dailyIncentive:   100,
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
    const { includeInactive } = req.query;
    const today     = todayIST();
    const filter    = { role: 'employee' };
    if (includeInactive !== 'true') filter.isActive = true;
    const employees = await User.find(filter).select('-password');
    const allJobs   = await Job.find({ assignedDate: today });
    const result = employees.map(emp => {
      const empJobs       = allJobs.filter(j => j.employeeId.toString() === emp._id.toString());
      const isActiveToday = emp.lastActiveDate === today && emp.isActive;
      return {
        ...emp.toObject(),
        isActiveToday,
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
    }).populate('customerId').sort({ sortOrder: 1 });
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
            carModel, carType, interiorType, phone, mapsLink } = req.body;
    if (!customerName) return res.status(400).send("customerName required");
    const location = await extractLatLng(mapsLink);
    const customer = await Customer.create({
      customerName, address, vehicleNumber, vehicleColor,
      carModel, carType,
      interiorType: interiorType || 'None',
      phone,
      mapsLink: mapsLink || null,
      location: location || { lat: null, lng: null },
    });
    res.json(customer);
  } catch (err) { res.status(500).send("Server error"); }
});

router.get('/customers', adminAuth, async (req, res) => {
  try {
    const { search, includeInactive } = req.query;
    const filter = { isActive: includeInactive === 'true' ? false : { $ne: false } };
    if (search) filter.customerName = { $regex: search, $options: 'i' };
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
    const now   = new Date();
    const ist   = new Date(now.getTime() + 5.5 * 60 * 60 * 1000);
    const month = parseInt(req.query.month) || (ist.getUTCMonth() + 1);
    const year  = parseInt(req.query.year)  || ist.getUTCFullYear();

    // Date range in UTC for the requested month (IST midnight boundaries)
    const from = new Date(`${year}-${String(month).padStart(2,'0')}-01T00:00:00+05:30`);
    const to   = month === 12
      ? new Date(`${year + 1}-01-01T00:00:00+05:30`)
      : new Date(`${year}-${String(month + 1).padStart(2,'0')}-01T00:00:00+05:30`);

    const jobs = await Job.find({
      customerId: req.params.id,
      $or: [
        { completedAt: { $gte: from, $lt: to } },
        { cancelledAt: { $gte: from, $lt: to } },
        { assignedDate: {
            $gte: `${year}-${String(month).padStart(2,'0')}-01`,
            $lt: month === 12
              ? `${year + 1}-01-01`
              : `${year}-${String(month + 1).padStart(2,'0')}-01`
          }
        },
      ],
    })
      .sort({ assignedDate: -1, createdAt: -1 })
      .populate('employeeId', 'name');

    // Summary counts
    const total     = jobs.length;
    const completed = jobs.filter(j => j.status === 'Completed').length;
    const cancelled = jobs.filter(j => j.status === 'Cancelled').length;
    // Complaints = unresolved OR resolved by reassignment (bad work regardless)
    const complaints = jobs.filter(j =>
        j.complaint?.raised === true &&
        (j.complaint?.resolved !== true ||
         j.complaint?.resolvedByReassign === true)).length;

    // Billable = Completed, no complaint OR complaint manually resolved by same employee
    const isBillable = (j) =>
        j.status === 'Completed' &&
        (!j.complaint?.raised ||
          (j.complaint?.resolved === true &&
           !j.complaint?.resolvedByReassign));

    const exteriorBillable = jobs.filter(j =>
        j.serviceType === 'Exterior' && isBillable(j)).length;
    const interiorBillable = jobs.filter(j =>
        (j.serviceType === 'Interior Standard' ||
         j.serviceType === 'Interior Premium') && isBillable(j)).length;

    res.json({ month, year, jobs, summary: {
      total, completed, cancelled, complaints,
      exteriorBillable, interiorBillable,
    }});
  } catch (err) { res.status(500).send("Server error"); }
});

router.put('/customers/:id', adminAuth, async (req, res) => {
  try {
    const { mapsLink } = req.body;
    const updates = { ...req.body };
    if (mapsLink !== undefined) {
      updates.location = await extractLatLng(mapsLink) || { lat: null, lng: null };
    }
    // When manually updating serviceCount, also stamp lastServiceMonth
    // so the next job completion increments from the new count correctly
    if (updates.serviceCount !== undefined) {
      const now      = new Date();
      const ist      = new Date(now.getTime() + 5.5 * 60 * 60 * 1000);
      const curMonth = `${ist.getUTCFullYear()}-${String(ist.getUTCMonth() + 1).padStart(2, '0')}`;
      updates.lastServiceMonth = curMonth;
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

// ── POST /admin/customers/:id/repair-count — recalculate serviceCount from actual jobs ──
router.post('/customers/:id/repair-count', adminAuth, async (req, res) => {
  try {
    const nowIST   = new Date(Date.now() + 5.5 * 60 * 60 * 1000);
    const curMonth = `${nowIST.getUTCFullYear()}-${String(nowIST.getUTCMonth() + 1).padStart(2, '0')}`;

    const allJobs = await Job.find({ customerId: req.params.id });
    const monthJobs = allJobs.filter(j =>
        j.assignedDate && j.assignedDate.startsWith(curMonth));

    // Count only billable completed jobs this month
    const billableCount = monthJobs.filter(j =>
        j.status === 'Completed' &&
        (!j.complaint?.raised ||
          (j.complaint?.resolved === true &&
           !j.complaint?.resolvedByReassign))).length;

    const customer = await Customer.findByIdAndUpdate(
      req.params.id,
      { $set: { serviceCount: billableCount, lastServiceMonth: curMonth } },
      { new: true }
    );
    if (!customer) return res.status(404).send('Customer not found');

    console.log(`[repair-count] customer=${req.params.id} corrected serviceCount to ${billableCount}`);
    res.json({ customerId: req.params.id, correctedCount: billableCount });
  } catch (err) { console.error(err); res.status(500).send('Server error'); }
});
router.put('/customers/:id/pricing', adminAuth, async (req, res) => {
  try {
    const { enabled, slabs, interiorStandard, interiorPremium } = req.body;
    const customer = await Customer.findByIdAndUpdate(
      req.params.id,
      { $set: { customPricing: { enabled: !!enabled, slabs: slabs || [], interiorStandard, interiorPremium } } },
      { new: true }
    );
    if (!customer) return res.status(404).send("Customer not found");
    res.json(customer);
  } catch (err) { res.status(500).send("Server error"); }
});

// ── GET /admin/customers/:id/monthly-counts — exterior + interior this month ──
router.get('/customers/:id/monthly-counts', adminAuth, async (req, res) => {
  try {
    const nowIST   = new Date(Date.now() + 5.5 * 60 * 60 * 1000);
    const yyyy     = nowIST.getUTCFullYear();
    const mm       = nowIST.getUTCMonth() + 1;
    const curMonth = `${yyyy}-${String(mm).padStart(2, '0')}`;

    // Fetch ALL jobs for this customer then filter in JS
    // avoids any string vs Date comparison issues with assignedDate
    const allJobs = await Job.find({ customerId: req.params.id });

    // Keep only jobs whose assignedDate falls in the current month
    const monthJobs = allJobs.filter(j => {
      if (!j.assignedDate) return false;
      // assignedDate is stored as "YYYY-MM-DD" string
      return j.assignedDate.startsWith(curMonth);
    });

    const isBillable = (j) =>
      j.status === 'Completed' &&
      (!j.complaint?.raised ||
        (j.complaint?.resolved === true && !j.complaint?.resolvedByReassign));

    const billable = monthJobs.filter(isBillable);
    const exterior = billable.filter(j => j.serviceType === 'Exterior').length;
    const interior = billable.filter(j =>
        j.serviceType === 'Interior Standard' ||
        j.serviceType === 'Interior Premium').length;

    console.log(`[monthly-counts] customer=${req.params.id} month=${curMonth} allJobs=${allJobs.length} monthJobs=${monthJobs.length} billable=${billable.length} ext=${exterior} int=${interior}`);
    monthJobs.forEach(j => console.log(`  job: status=${j.status} type=${j.serviceType} date=${j.assignedDate} billable=${isBillable(j)}`));

    res.json({ exterior, interior, total: exterior + interior });
  } catch (err) {
    console.error('[monthly-counts] error:', err);
    res.status(500).send('Server error');
  }
});

// ── Holidays config ───────────────────────────────────────────────────────────
// Stored as { "YYYY-MM": ["YYYY-MM-DD", ...] } — keyed by month
router.get('/config/holidays', adminAuth, async (req, res) => {
  try {
    const doc = await Config.findOne({ key: 'holidays' });
    res.json(doc?.value || {});
  } catch (err) { console.error(err); res.status(500).send('Server error'); }
});

router.put('/config/holidays', adminAuth, async (req, res) => {
  try {
    // req.body: { month: "YYYY-MM", dates: ["YYYY-MM-DD", ...] }
    const { month, dates } = req.body;
    const doc = await Config.findOne({ key: 'holidays' });
    const current = doc?.value || {};
    current[month] = dates || [];
    await Config.findOneAndUpdate(
      { key: 'holidays' },
      { key: 'holidays', value: current },
      { upsert: true }
    );
    res.json(current);
  } catch (err) { console.error(err); res.status(500).send('Server error'); }
});
// ═══════════════════════════════════════════════════════════════════════════
router.post('/assign', adminAuth, async (req, res) => {
  try {
    const { customerId, employeeId, serviceType, assignedDate } = req.body;
    if (!customerId || !employeeId || !serviceType)
      return res.status(400).send("customerId, employeeId, serviceType required");
    const today    = assignedDate || todayIST();

    // Determine service category: 'Exterior' or 'Interior'
    const category = (serviceType === 'Exterior') ? 'Exterior' : 'Interior';
    const catTypes  = category === 'Exterior'
      ? ['Exterior']
      : ['Interior Standard', 'Interior Premium'];

    // Block only if same service CATEGORY already assigned (non-cancelled)
    // e.g. can assign Exterior + Interior Standard to same customer same day
    const existing = await Job.findOne({
      customerId,
      assignedDate: today,
      serviceType:  { $in: catTypes },
      status:       { $nin: ['Cancelled'] },
    });
    if (existing)
      return res.status(400).send(
        `Customer already has a ${category} job assigned today`);

    // Block assignment if employee has already completed towel soak for today
    // (means their day is done — no new jobs should be added)
    if (today === todayIST()) {
      const Attendance = require('../models/attendance');
      const attRecord  = await Attendance.findOne({
        employeeId, date: today });
      if (attRecord?.towelSoakUrl) {
        const isSat = new Date(today + 'T12:00:00Z').getUTCDay() === 6;
        // On Saturday, also need duster soak to be fully done
        const dayDone = isSat
          ? (attRecord.towelSoakUrl && attRecord.dusterSoakUrl)
          : true;
        if (dayDone)
          return res.status(400).send(
            "Employee has already completed their day (towel soak uploaded). Cannot assign new jobs.");
      }
    }

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

// Invoice pricing config
const DEFAULT_INVOICE_PRICING = {
  slabs: [
    { from: 1,  to: 5,    hatchback: 0, sedan: 0, suv: 0 },
    { from: 6,  to: 10,   hatchback: 0, sedan: 0, suv: 0 },
    { from: 11, to: null, hatchback: 0, sedan: 0, suv: 0 },
  ],
  interiorStandard: 0,
  interiorPremium:  0,
  contacts: [
    { name: '', number: '', qrImageUrl: null },
    { name: '', number: '', qrImageUrl: null },
  ],
};

router.get('/config/invoicePricing', adminAuth, async (req, res) => {
  try {
    const doc = await Config.findOne({ key: 'invoicePricing' });
    res.json(doc ? doc.value : DEFAULT_INVOICE_PRICING);
  } catch (err) { res.status(500).send("Server error"); }
});

router.put('/config/invoicePricing', adminAuth, async (req, res) => {
  try {
    const updated = await Config.findOneAndUpdate(
      { key: 'invoicePricing' },
      { key: 'invoicePricing', value: req.body },
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
      status:      { $in: ['Completed', 'Cancelled'] },
      $or: [
        { completedAt: { $gte: from, $lt: to } },
        { cancelledAt: { $gte: from, $lt: to } },
      ],
    }).populate('customerId', 'customerName carType carModel vehicleNumber mapsLink location');

    // Helper: job earns wages only if completed with no unresolved complaint
    // Job earns wages only if completed with no complaint,
    // or complaint was manually resolved (same employee fixed it).
    // resolvedByReassign = true means another employee did the work — not payable.
    const isPayable = (job) =>
      job.status === 'Completed' &&
      (!job.complaint?.raised ||
        (job.complaint?.resolved === true &&
         !job.complaint?.resolvedByReassign));

    // Group by date (IST) — only payable jobs count for distance
    const byDate = {};
    for (const job of jobs) {
      const ts  = job.completedAt || job.cancelledAt;
      if (!ts) continue;
      const ist = new Date(ts.getTime() + 5.5 * 60 * 60 * 1000);
      const dk  = ist.toISOString().split('T')[0];
      if (!byDate[dk]) byDate[dk] = [];
      byDate[dk].push(job);
    }

    const jobDetails    = [];
    const dayDetails    = {}; // keyed by date — per-day aggregates
    const carTypeCounts = { Hatchback: 0, Sedan: 0, SUV: 0 };
    let totalJobEarnings       = 0;
    let totalDistanceKm        = 0;
    let totalDistanceEarnings  = 0;
    let totalSkippedCustomers  = 0;

    const home = employee.homeLocation?.lat ? employee.homeLocation : null;

    // ── Pass 1: sync — compute earnings, build jobDetails, collect waypoints ──
    const distanceTasks = []; // { date, routePoints } — fired in parallel later

    for (const [date, dayJobs] of Object.entries(byDate).sort()) {
      dayDetails[date] = {
        date,
        jobCount:         0,
        carCounts:        { Hatchback: 0, Sedan: 0, SUV: 0 },
        jobEarnings:      0,
        distanceKm:       0,
        distanceEarnings: 0,
        incentive:        0,
        incentiveEarned:  false,
        incentiveReasons: [],
        dayTotal:         0,
      };

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
          else carTypeCounts['Hatchback']++;
          totalJobEarnings += earnings;
          dayDetails[date].jobEarnings += earnings;
          dayDetails[date].jobCount++;
          if (dayDetails[date].carCounts[carType] !== undefined)
            dayDetails[date].carCounts[carType]++;
          else dayDetails[date].carCounts['Hatchback']++;
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

      // Collect waypoints for this day (extractLatLng is fast — uses cached coords)
      if (home) {
        const eligibleJobs = dayJobs
          .filter(job => {
            const payable = isPayable(job);
            return (job.status === 'Completed' && payable) ||
                    job.status === 'Cancelled';
          })
          .sort((a, b) => (a.sortOrder || 0) - (b.sortOrder || 0));

        const waypoints = [];
        let skipped = 0;
        for (const job of eligibleJobs) {
          const customer = job.customerId;
          let coords = null;
          if (customer?.location?.lat) {
            coords = { lat: customer.location.lat, lng: customer.location.lng };
          } else if (customer?.mapsLink) {
            coords = await extractLatLng(customer.mapsLink);
          }
          if (coords) waypoints.push(coords);
          else skipped++;
        }

        if (waypoints.length > 0) {
          distanceTasks.push({ date, routePoints: [home, ...waypoints, home], skipped });
        }
      }
    }

    // Fetch attendance records early — needed for both distance cache and incentive
    const attendanceRecords = await Attendance.find({
      employeeId,
      date: { $gte: from.toISOString().split('T')[0], $lte: to.toISOString().split('T')[0] },
    });
    const attByDate = {};
    for (const r of attendanceRecords) attByDate[r.date] = r;

    // Helper: is the day safe to cache distance
    // Past days are always final — cache regardless of towel soak
    // Today: still require towel soak (jobs may still be added)
    const todayStr = todayIST();
    const isDayComplete = (date) => {
      if (date < todayStr) return true; // past day — always cache
      const r = attByDate[date];
      if (!r) return false;
      const isSat = new Date(date + 'T12:00:00Z').getUTCDay() === 6;
      return isSat
        ? !!(r.towelSoakUrl && r.dusterSoakUrl)
        : !!r.towelSoakUrl;
    };

    // ── Pass 2: distance — read from cache or call Google API ────────────────
    // For complete days: check attendance.distanceKm first (free)
    // Only call Google API for days without a cached value
    // After computing, write back to attendance record for future calls

    // Split into cached and uncached
    const cachedDates   = [];
    const uncachedTasks = [];

    for (const { date, routePoints, skipped } of distanceTasks) {
      const rec    = attByDate[date];
      const cached = rec?.distanceKm;
      if (isDayComplete(date) && cached != null) {
        // Use cached value — free
        cachedDates.push({ date, dayKm: cached, skipped });
      } else {
        // Need to call Google API
        uncachedTasks.push({ date, routePoints, skipped, rec });
      }
    }

    // Apply cached results immediately
    for (const { date, dayKm, skipped } of cachedDates) {
      const dayDistEarn = halfDownRound(dayKm * (pricing.distancePerKm ?? 2));
      totalDistanceKm       += dayKm;
      totalDistanceEarnings += dayDistEarn;
      dayDetails[date].distanceKm       = parseFloat(dayKm.toFixed(2));
      dayDetails[date].distanceEarnings = dayDistEarn;
      if (skipped > 0) totalSkippedCustomers += skipped;
    }

    // Fire uncached API calls in parallel
    if (uncachedTasks.length > 0) {
      const distResults = await Promise.all(
        uncachedTasks.map(({ date, routePoints, skipped, rec }) =>
          computeDayDistanceKm(routePoints).then(async dayKm => {
            // Cache the result if the day is complete
            if (isDayComplete(date) && rec) {
              await Attendance.findByIdAndUpdate(rec._id,
                { $set: { distanceKm: parseFloat(dayKm.toFixed(2)) } });
            }
            return { date, dayKm, skipped,
              dayDistEarn: halfDownRound(dayKm * (pricing.distancePerKm ?? 2)) };
          })
        )
      );
      for (const { date, dayKm, skipped, dayDistEarn } of distResults) {
        totalDistanceKm       += dayKm;
        totalDistanceEarnings += dayDistEarn;
        dayDetails[date].distanceKm       = parseFloat(dayKm.toFixed(2));
        dayDetails[date].distanceEarnings = dayDistEarn;
        if (skipped > 0) totalSkippedCustomers += skipped;
      }
    }

    const complainedJobs  = jobs.filter(j => j.complaint?.raised && !j.complaint?.resolved);
    const resolvedJobs    = jobs.filter(j => j.complaint?.raised &&  j.complaint?.resolved);

    // ── Pass 3: compute incentive for all days in parallel ────────────────────
    let totalIncentive = 0;
    const incentiveDetails = [];
    const incResults = await Promise.all(
      attendanceRecords.map(record =>
        computeIncentive(record, employeeId, record.date, pricing)
          .then(inc => ({ record, inc }))
      )
    );
    for (const { record, inc } of incResults) {
      if (inc.earned) totalIncentive += inc.amount;
      incentiveDetails.push({
        date:     record.date,
        earned:   inc.earned,
        excused:  inc.excused || false,
        amount:   inc.amount,
        reasons:  inc.reasons,
      });
      if (dayDetails[record.date]) {
        dayDetails[record.date].incentive        = inc.earned ? inc.amount : 0;
        dayDetails[record.date].incentiveEarned  = inc.earned;
        dayDetails[record.date].incentiveReasons = inc.reasons;
      }
    }

    // Compute dayTotal for each day
    for (const d of Object.values(dayDetails)) {
      d.dayTotal = halfDownRound(
        d.jobEarnings + d.distanceEarnings + d.incentive);
    }

    // ── Attendance — days worked + total working days ────────────────────────
    const curMonth    = `${year}-${String(month).padStart(2,'0')}`;
    const attendances = await Attendance.find({
      employeeId,
      date: {
        $gte: `${curMonth}-01`,
        $lt:  month === 12
          ? `${year+1}-01-01`
          : `${year}-${String(month+1).padStart(2,'0')}-01`,
      },
    });

    // Fetch declared holidays for this month
    const holidayDoc  = await Config.findOne({ key: 'holidays' });
    const holidays    = new Set((holidayDoc?.value?.[curMonth] || []));

    const workedDates    = new Set(attendances.map(a => a.date));
    const daysWorked     = workedDates.size;
    const daysInMonth    = new Date(year, month, 0).getDate();
    let totalWorkingDays = 0;
    for (let d = 1; d <= daysInMonth; d++) {
      const dow = new Date(year, month - 1, d).getDay(); // 0 = Sunday
      const dk  = `${curMonth}-${String(d).padStart(2, '0')}`;
      if (holidays.has(dk)) continue;     // declared holiday — skip
      if (dow !== 0) {
        totalWorkingDays++;               // non-Sunday always counts
      } else if (workedDates.has(dk)) {
        totalWorkingDays++;               // Sunday only if worked
      }
    }

    res.json({
      employee: { id: employee._id, name: employee.name, email: employee.email,
                  hasHomeLocation: !!home },
      month, year, pricing,
      summary: {
        totalJobs:            jobs.length,
        complainedJobs:       complainedJobs.length,
        resolvedComplaints:   resolvedJobs.length,
        carTypeCounts,
        totalJobEarnings:     halfDownRound(totalJobEarnings),
        totalDistanceKm:      parseFloat(totalDistanceKm.toFixed(2)),
        totalDistanceEarnings:halfDownRound(totalDistanceEarnings),
        totalIncentive:       halfDownRound(totalIncentive),
        grandTotal:           halfDownRound(totalJobEarnings + totalDistanceEarnings + totalIncentive),
        skippedCustomers:     totalSkippedCustomers,
        daysWorked,
        totalWorkingDays,
      },
      jobDetails,
      dayDetails: Object.values(dayDetails).sort((a, b) => a.date.localeCompare(b.date)),
      incentiveDetails,
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

    // Decrement monthly serviceCount on customer (floor at 0)
    await Customer.findByIdAndUpdate(job.customerId,
      { $inc: { serviceCount: -1 } });
    // Note: if this drops below 0 the migration script will correct it

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

    // Restore serviceCount only if complaint was raised in the current month
    // (cross-month complaints don't affect the new month's count)
    const nowIST   = new Date(Date.now() + 5.5 * 60 * 60 * 1000);
    const curMonth = `${nowIST.getUTCFullYear()}-${String(nowIST.getUTCMonth() + 1).padStart(2, '0')}`;
    const cust     = await Customer.findById(job.customerId);
    if (cust?.lastServiceMonth === curMonth) {
      await Customer.findByIdAndUpdate(job.customerId,
        { $inc: { serviceCount: 1 } });
    }

    // resolvedBy: optional body param — name of who resolved it (admin or employee)
    const resolvedBy = req.body?.resolvedBy || 'Admin';

    const updated = await Job.findByIdAndUpdate(
      req.params.jobId,
      {
        'complaint.resolved':   true,
        'complaint.resolvedAt': new Date(),
        'complaint.resolvedBy': resolvedBy,
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

// Helper: compute incentive eligibility for one attendance record + day's jobs
// Returns { earned: bool, reasons: string[] }
async function computeIncentive(record, employeeId, date, pricing) {
  const incentiveAmt  = pricing.dailyIncentive ?? 100;
  const isSaturday    = new Date(date + 'T12:00:00Z').getUTCDay() === 6;
  const reasons       = [];

  if (!record) return { earned: false, amount: 0, reasons: ['No attendance record for this day'] };
  if (record.incentiveExcused) return { earned: true, excused: true, amount: incentiveAmt, reasons: [] };

  // 1. Selfie approved
  if (record.selfieApproval !== 'approved') reasons.push('selfie');

  // 2. Towels approved
  if (record.towelsApproval !== 'approved') reasons.push('towels');

  // 3. Towel soak uploaded + approved
  if (!record.towelSoakUrl) reasons.push('towelSoakMissing');
  else if (record.towelSoakApproval !== 'approved') reasons.push('towelSoak');

  // 4. Duster soak uploaded + approved (Saturdays only)
  if (isSaturday) {
    if (!record.dusterSoakUrl) reasons.push('dusterSoakMissing');
    else if (record.dusterSoakApproval !== 'approved') reasons.push('dusterSoak');
  }

  // 5. Before photo of first job on or before 06:15 IST
  // If sortOrder:1 job was cancelled (no beforeUploadedAt), use cancelledAt
  // or fall back to the earliest job with a beforeUploadedAt
  const firstJob = await Job.findOne({ employeeId, assignedDate: date })
    .sort({ sortOrder: 1 });
  const startTs = firstJob?.beforeUploadedAt
    || (firstJob?.status === 'Cancelled' ? firstJob?.cancelledAt : null)
    || (await Job.findOne({
          employeeId, assignedDate: date,
          beforeUploadedAt: { $ne: null }
        }).sort({ beforeUploadedAt: 1 }))?.beforeUploadedAt;
  if (startTs) {
    const ist  = new Date(new Date(startTs).getTime() + 5.5 * 60 * 60 * 1000);
    const hhmm = ist.getUTCHours() * 60 + ist.getUTCMinutes();
    if (hhmm > 6 * 60 + 15) reasons.push('late'); // after 06:15
  } else {
    reasons.push('late'); // no timestamp at all
  }

  // 6. Minimum 5 completed cars for the day
  const completedCount = await Job.countDocuments({
    employeeId,
    assignedDate: date,
    status: 'Completed',
  });
  if (completedCount < 5) reasons.push('minCars');

  // 7. No complaints raised that day (unresolved OR resolved by reassignment)
  // resolvedByReassign = another employee fixed it — Dinesh still had bad work
  const complainedJob = await Job.findOne({
    employeeId,
    assignedDate: date,
    'complaint.raised': true,
    $or: [
      { 'complaint.resolved':  { $ne: true } },           // unresolved
      { 'complaint.resolvedByReassign': true },            // resolved by someone else
    ],
  });
  if (complainedJob) reasons.push('complaint');

  return {
    earned:  reasons.length === 0,
    amount:  reasons.length === 0 ? incentiveAmt : 0,
    reasons,
    isSaturday,
  };
}

// GET /attendance/my-status/:employeeId?date= — employee-facing, no auth
// Returns just the fields the employee app needs (no sensitive admin data)
router.get('/attendance/my-status/:employeeId', async (req, res) => {
  try {
    const date   = req.query.date || todayIST();
    const record = await Attendance.findOne({
      employeeId: req.params.employeeId, date });
    if (!record) return res.json({ exists: false });
    res.json({
      exists:           true,
      selfieUrl:        record.selfieUrl        || null,
      selfieUploadedAt: record.selfieUploadedAt || record.createdAt || null,
      towelUrls:        record.towelUrls        || [],
      towelSoakUrl:     record.towelSoakUrl     || null,
      dusterSoakUrl:    record.dusterSoakUrl    || null,
    });
  } catch (err) { res.status(500).send("Server error"); }
});

// POST /admin/reset-day/:employeeId?date=YYYY-MM-DD
// Testing only — hard deletes all jobs + attendance for an employee on a date
// Restores customer service counts for any completed jobs
router.post('/reset-day/:employeeId', adminAuth, async (req, res) => {
  try {
    const empId = req.params.employeeId;
    const date  = req.query.date || todayIST();

    // 1. Find all jobs for this employee on this date
    const jobs = await Job.find({ employeeId: empId, assignedDate: date });

    // 2. For each completed job, decrement the customer's serviceCount
    const completedJobs = jobs.filter(j => j.status === 'Completed');
    await Promise.all(completedJobs.map(j =>
      Customer.findByIdAndUpdate(j.customerId, { $inc: { serviceCount: -1 } })
    ));

    // 3. Hard delete all jobs for this employee on this date
    const jobResult = await Job.deleteMany({ employeeId: empId, assignedDate: date });

    // 4. Delete the attendance record
    const attResult = await Attendance.deleteOne({ employeeId: empId, date });

    res.json({
      success:         true,
      jobsDeleted:     jobResult.deletedCount,
      attendanceReset: attResult.deletedCount > 0,
      serviceCountsRestored: completedJobs.length,
    });
  } catch (err) {
    console.error('[reset-day]', err);
    res.status(500).send('Server error');
  }
});
router.get('/attendance/:employeeId', adminAuth, async (req, res) => {
  try {
    const date     = req.query.date || todayIST();
    const empId    = req.params.employeeId;

    const record = await Attendance.findOne({ employeeId: empId, date });

    const configDoc = await Config.findOne({ key: 'pricing' });
    const pricing   = configDoc ? configDoc.value : DEFAULT_PRICING;

    const response = record
      ? {
          ...record.toObject(),
          // selfieUploadedAt may be null for records created before this field was added
          // fall back to createdAt (time attendance record was first created = selfie upload time)
          selfieUploadedAt: record.selfieUploadedAt || record.createdAt || null,
        }
      : { selfieUrl: null, towelUrls: [], date,
          selfieApproval: 'pending', towelsApproval: 'pending',
          towelSoakApproval: 'pending', dusterSoakApproval: 'pending',
          incentiveExcused: false };

    // Incentive computation
    const incentive = await computeIncentive(record, empId, date, pricing);
    response.incentive = incentive;

    res.json(response);
  } catch (err) { console.error(err); res.status(500).send("Server error"); }
});

// PATCH /admin/attendance/:employeeId/approve?date=YYYY-MM-DD
// body: { type: 'selfie'|'towels'|'towelSoak'|'dusterSoak', status: 'approved'|'rejected'|'pending' }
router.patch('/attendance/:employeeId/approve', adminAuth, async (req, res) => {
  try {
    const date   = req.query.date || todayIST();
    const { type, status } = req.body;

    const fieldMap = {
      selfie:     'selfieApproval',
      towels:     'towelsApproval',
      towelSoak:  'towelSoakApproval',
      dusterSoak: 'dusterSoakApproval',
    };
    const field = fieldMap[type];
    if (!field) return res.status(400).send("Invalid type");
    if (!['approved', 'rejected', 'pending'].includes(status))
      return res.status(400).send("Invalid status");

    const record = await Attendance.findOneAndUpdate(
      { employeeId: req.params.employeeId, date },
      { $set: { [field]: status } },
      { upsert: true, new: true }
    );
    res.json(record);
  } catch (err) { console.error(err); res.status(500).send("Server error"); }
});

// PATCH /admin/attendance/:employeeId/excuse?date=YYYY-MM-DD
// Excuse pass — grants incentive regardless of criteria
router.patch('/attendance/:employeeId/excuse', adminAuth, async (req, res) => {
  try {
    const date   = req.query.date || todayIST();
    const { excused } = req.body; // true or false

    const record = await Attendance.findOneAndUpdate(
      { employeeId: req.params.employeeId, date },
      { $set: { incentiveExcused: !!excused } },
      { upsert: true, new: true }
    );
    res.json(record);
  } catch (err) { console.error(err); res.status(500).send("Server error"); }
});

// GET /admin/attendance/:employeeId/incentive-status?date=YYYY-MM-DD
// Used by employee app incentive tab — returns criteria breakdown for date
router.get('/attendance/:employeeId/incentive-status', async (req, res) => {
  try {
    const date    = req.query.date || todayIST();
    const empId   = req.params.employeeId;
    const record  = await Attendance.findOne({ employeeId: empId, date });

    const configDoc = await Config.findOne({ key: 'pricing' });
    const pricing   = configDoc ? configDoc.value : DEFAULT_PRICING;

    const incentive = await computeIncentive(record, empId, date, pricing);

    // Include login time (selfieUploadedAt) for employee display
    let loginTime = null;
    if (record?.selfieUploadedAt || record?.createdAt) {
      const raw  = record.selfieUploadedAt || record.createdAt;
      const ist  = new Date(new Date(raw).getTime() + 5.5 * 60 * 60 * 1000);
      const h24  = ist.getUTCHours();
      const h12  = h24 === 0 ? 12 : h24 > 12 ? h24 - 12 : h24;
      const ampm = h24 < 12 ? 'AM' : 'PM';
      const mm   = String(ist.getUTCMinutes()).padStart(2, '0');
      loginTime  = `${h12}:${mm} ${ampm}`;
    }

    res.json({ date, ...incentive, loginTime });
  } catch (err) { console.error(err); res.status(500).send("Server error"); }
});

// ── GET /admin/interior/todo?month=&year= ─────────────────────────────────────
// Returns customers with interior type who haven't had interior done this month
// Ordered by last month's completion date ascending
router.get('/interior/todo', adminAuth, async (req, res) => {
  try {
    const now   = new Date();
    const month = parseInt(req.query.month) || (now.getMonth() + 1);
    const year  = parseInt(req.query.year)  || now.getFullYear();

    // Current month range
    const from = new Date(year, month - 1, 1);
    const to   = new Date(year, month, 1);

    // Previous month range
    const prevMonth = month === 1 ? 12 : month - 1;
    const prevYear  = month === 1 ? year - 1 : year;
    const prevFrom  = new Date(prevYear, prevMonth - 1, 1);
    const prevTo    = new Date(prevYear, prevMonth, 1);

    // All customers with interior type set
    const customers = await Customer.find({
      interiorType: { $in: ['Interior Standard', 'Interior Premium'] }
    });

    // Jobs completed this month that are interior type
    const doneThisMonth = await Job.find({
      serviceType: { $in: ['Interior Standard', 'Interior Premium'] },
      status:      'Completed',
      completedAt: { $gte: from, $lt: to },
    }).select('customerId completedAt');

    const doneCustomerIds = new Set(
      doneThisMonth.map(j => j.customerId.toString()));

    // Customers not done this month = to-do
    const todoCustomers = customers.filter(
      c => !doneCustomerIds.has(c._id.toString()));

    // For each to-do customer find last month's completion date
    const lastMonthJobs = await Job.find({
      customerId:  { $in: todoCustomers.map(c => c._id) },
      serviceType: { $in: ['Interior Standard', 'Interior Premium'] },
      status:      'Completed',
      completedAt: { $gte: prevFrom, $lt: prevTo },
    }).select('customerId completedAt');

    const lastMonthMap = {};
    for (const j of lastMonthJobs) {
      lastMonthMap[j.customerId.toString()] = j.completedAt;
    }

    // Build result with category for filtering
    const result = todoCustomers.map(c => {
      const lastDone  = lastMonthMap[c._id.toString()] || null;
      const isNew     = c.createdAt >= from;
      const doneLastMonth = !!lastDone;
      return {
        _id:          c._id,
        customerName: c.customerName,
        interiorType: c.interiorType,
        vehicleNumber:c.vehicleNumber,
        carModel:     c.carModel,
        carType:      c.carType,
        lastDoneDate: lastDone,
        isNew,
        doneLastMonth,
      };
    });

    // Sort: done last month by date asc, then not done last month, then new
    result.sort((a, b) => {
      if (a.doneLastMonth && b.doneLastMonth)
        return new Date(a.lastDoneDate) - new Date(b.lastDoneDate);
      if (a.doneLastMonth) return -1;
      if (b.doneLastMonth) return 1;
      if (a.isNew && !b.isNew) return 1;
      if (!a.isNew && b.isNew) return -1;
      return a.customerName.localeCompare(b.customerName);
    });

    res.json({ month, year, customers: result });
  } catch (err) { console.error(err); res.status(500).send('Server error'); }
});

// ── GET /admin/interior/history?month=&year= ──────────────────────────────────
// Returns completed interior jobs for the month, desc by completedAt
router.get('/interior/history', adminAuth, async (req, res) => {
  try {
    const now   = new Date();
    const month = parseInt(req.query.month) || (now.getMonth() + 1);
    const year  = parseInt(req.query.year)  || now.getFullYear();
    const from  = new Date(year, month - 1, 1);
    const to    = new Date(year, month, 1);

    const jobs = await Job.find({
      serviceType: { $in: ['Interior Standard', 'Interior Premium'] },
      status:      'Completed',
      completedAt: { $gte: from, $lt: to },
    })
      .populate('customerId', 'customerName vehicleNumber carModel carType')
      .populate('employeeId', 'name')
      .sort({ completedAt: -1 });

    const result = jobs.map(j => ({
      jobId:        j._id,
      customerId:   j.customerId?._id,
      customerName: j.customerId?.customerName || '',
      vehicleNumber:j.customerId?.vehicleNumber || '',
      carModel:     j.customerId?.carModel || '',
      carType:      j.customerId?.carType || '',
      interiorType: j.serviceType,
      completedAt:  j.completedAt,
      employeeName: j.employeeId?.name || '',
    }));

    res.json({ month, year, jobs: result });
  } catch (err) { console.error(err); res.status(500).send('Server error'); }
});

// ── POST /admin/jobs/:jobId/revert ────────────────────────────────────────────
// Reverts an In Progress or Completed job back to Pending.
// Clears all photo fields and timestamps in DB (S3 files kept).
// If job was Completed, decrements customer serviceCount.
// Blocked if complaint is raised on the job.
router.post('/jobs/:jobId/revert', adminAuth, async (req, res) => {
  try {
    const job = await Job.findById(req.params.jobId);
    if (!job) return res.status(404).send("Job not found");

    if (!['In Progress', 'Completed'].includes(job.status)) {
      return res.status(400).send("Only In Progress or Completed jobs can be reverted");
    }
    if (job.complaint?.raised) {
      return res.status(400).send(
        "Cannot revert a job with a complaint raised. Use reassign instead.");
    }

    const wasCompleted = job.status === 'Completed';

    // Use $set to clear all fields atomically — avoids Mongoose subdoc array issues
    await Job.findByIdAndUpdate(job._id, {
      $set: {
        status:                 'Pending',
        beforeUploadedAt:       null,
        completedAt:            null,
        serviceCount:           0,
        'images.before':        null,
        'images.after':         [],
        'images.interiorBefore': [],
        'images.interiorAfter':  [],
      },
    });

    // Decrement customer serviceCount if job was completed
    if (wasCompleted) {
      const nowIST   = new Date(Date.now() + 5.5 * 60 * 60 * 1000);
      const curMonth = `${nowIST.getUTCFullYear()}-${String(nowIST.getUTCMonth() + 1).padStart(2, '0')}`;
      const cust     = await Customer.findById(job.customerId);
      if (cust?.lastServiceMonth === curMonth && cust.serviceCount > 0) {
        await Customer.findByIdAndUpdate(job.customerId,
          { $inc: { serviceCount: -1 } });
      }
    }

    const populated = await Job.findById(job._id).populate('customerId');
    res.json(populated);
  } catch (err) { console.error(err); res.status(500).send("Server error"); }
});

// ── POST /admin/jobs/:jobId/reassign ──────────────────────────────────────────
// Reassigns a complained job to another employee.
// Creates a fresh Pending job for the new employee.
// Bypasses duplicate customer check (intentional reassignment).
// When the new job completes, the original complaint auto-resolves.
router.post('/jobs/:jobId/reassign', adminAuth, async (req, res) => {
  try {
    const { employeeId } = req.body;
    if (!employeeId) return res.status(400).send("employeeId required");

    const originalJob = await Job.findById(req.params.jobId)
        .populate('employeeId', 'name');
    if (!originalJob) return res.status(404).send("Job not found");
    if (!originalJob.complaint?.raised) {
      return res.status(400).send("Job must have a complaint to be reassigned");
    }
    if (originalJob.reassignedJobId) {
      return res.status(400).send("Job already reassigned");
    }

    const newEmployee = await User.findById(employeeId).select('name');
    if (!newEmployee) return res.status(404).send("Employee not found");

    const today = todayIST();

    // Get next sortOrder for new employee
    const lastJob = await Job.findOne({ employeeId, assignedDate: today })
        .sort({ sortOrder: -1 });
    const sortOrder = lastJob ? lastJob.sortOrder + 1 : 1;

    // Create fresh job for new employee — bypass duplicate check
    const newJob = await Job.create({
      customerId:   originalJob.customerId,
      employeeId,
      serviceType:  originalJob.serviceType,
      assignedDate: today,
      sortOrder,
      status:       'Pending',
      originalJobId: originalJob._id,
    });

    // Link original job to new job
    await Job.findByIdAndUpdate(originalJob._id, {
      reassignedJobId: newJob._id,
    });

    const populated = await Job.findById(newJob._id).populate('customerId');
    res.json({ originalJob: originalJob._id, newJob: populated });
  } catch (err) { console.error(err); res.status(500).send("Server error"); }
});

// ═══════════════════════════════════════════════════════════════════════════
// INVOICE ENDPOINTS
// ═══════════════════════════════════════════════════════════════════════════

// Helper: compute invoice for a customer for a given month
async function computeCustomerInvoice(customer, jobs, globalPricing) {
  // Use customer custom pricing if enabled, else fall back to global
  const pricing = (customer.customPricing?.enabled && customer.customPricing?.slabs?.length)
    ? customer.customPricing
    : globalPricing;
  const isBillable = (j) =>
    j.status === 'Completed' &&
    (!j.complaint?.raised ||
      (j.complaint?.resolved === true && !j.complaint?.resolvedByReassign));

  const billableJobs  = jobs.filter(isBillable);

  // Legacy totals
  const attempted     = jobs.length;
  const cancelled     = jobs.filter(j => j.status === 'Cancelled').length;
  const cleaned       = billableJobs.length;

  // Split stats — exterior
  const extAllJobs    = jobs.filter(j => j.serviceType === 'Exterior');
  const extAttempted  = extAllJobs.length;
  const extCleaned    = extAllJobs.filter(isBillable).length;
  const extCancelled  = extAllJobs.filter(j => j.status === 'Cancelled').length;

  // Split stats — interior
  const intAllJobs    = jobs.filter(j =>
      j.serviceType === 'Interior Standard' || j.serviceType === 'Interior Premium');
  const intAttempted  = intAllJobs.length;
  const intCleaned    = intAllJobs.filter(isBillable).length;
  const intCancelled  = intAllJobs.filter(j => j.status === 'Cancelled').length;

  const exteriorJobs  = billableJobs.filter(j => j.serviceType === 'Exterior');
  const intStdJobs    = billableJobs.filter(j => j.serviceType === 'Interior Standard');
  const intPremJobs   = billableJobs.filter(j => j.serviceType === 'Interior Premium');

  const extCount      = exteriorJobs.length;
  const lineItems     = [];
  let   grandTotal    = 0;

  // Exterior — find slab for extCount
  if (extCount > 0) {
    const slabs = pricing.slabs || [];
    let pricePerWash = 0;
    for (const slab of slabs) {
      const inSlab = slab.to === null
        ? extCount >= slab.from
        : extCount >= slab.from && extCount <= slab.to;
      if (inSlab) {
        const carType = (customer.carType || 'Hatchback').toLowerCase();
        pricePerWash = slab[carType] ?? slab['hatchback'] ?? 0;
        break;
      }
    }
    const extAmount = extCount * pricePerWash;
    lineItems.push({ label: customer.carType || 'Hatchback', amount: extAmount });
    grandTotal += extAmount;
  }

  // Interior Standard
  if (intStdJobs.length > 0) {
    const amt = intStdJobs.length * (pricing.interiorStandard ?? 0);
    lineItems.push({ label: 'Interior Standard', amount: amt });
    grandTotal += amt;
  }

  // Interior Premium
  if (intPremJobs.length > 0) {
    const amt = intPremJobs.length * (pricing.interiorPremium ?? 0);
    lineItems.push({ label: 'Interior Premium', amount: amt });
    grandTotal += amt;
  }

  return {
    attempted, cleaned, cancelled,
    extAttempted, extCleaned, extCancelled,
    intAttempted, intCleaned, intCancelled,
    lineItems: lineItems.map(i => ({ ...i, amount: Math.round(i.amount) })),
    grandTotal: Math.round(grandTotal),
  };
}

// ── GET /admin/invoice/list?month=&year= ──────────────────────────────────────
// Returns customers with invoice summary. Car groups appear as one combined card.
router.get('/invoice/list', adminAuth, async (req, res) => {
  try {
    const now   = new Date();
    const ist   = new Date(now.getTime() + 5.5 * 60 * 60 * 1000);
    const month = parseInt(req.query.month) || (ist.getUTCMonth() + 1);
    const year  = parseInt(req.query.year)  || ist.getUTCFullYear();

    const curMonth = `${year}-${String(month).padStart(2,'0')}`;

    const configDoc = await Config.findOne({ key: 'invoicePricing' });
    const pricing   = configDoc?.value || {};
    const customers = await Customer.find({ isActive: { $ne: false } });

    const allJobsRaw = await Job.find({
      assignedDate: {
        $gte: `${curMonth}-01`,
        $lt:  month === 12
          ? `${year+1}-01-01`
          : `${year}-${String(month+1).padStart(2,'0')}-01`,
      },
    });

    const jobsByCustomer = {};
    for (const job of allJobsRaw) {
      const cid = job.customerId.toString();
      if (!jobsByCustomer[cid]) jobsByCustomer[cid] = [];
      jobsByCustomer[cid].push(job);
    }

    const existingInvoices = await Invoice.find({ month, year });
    const invoiceByCustomer = {};
    for (const inv of existingInvoices) {
      invoiceByCustomer[inv.customerId.toString()] = inv;
    }

    // Track which groupIds we've already added to avoid duplicate group cards
    const processedGroups = new Set();
    const result = [];

    for (const customer of customers) {
      const cid  = customer._id.toString();
      const jobs = jobsByCustomer[cid] || [];

      // If customer is in a group, handle as combined card
      if (customer.carGroupId && customer.carGroupId.toString().trim() !== '') {
        const gid = customer.carGroupId.toString();
        if (processedGroups.has(gid)) continue;
        processedGroups.add(gid);

        // Find all group members
        const members = customers.filter(c =>
            c.carGroupId && c.carGroupId.toString() === gid);

        // Check if any member has activity this month
        const hasActivity = members.some(m =>
            (jobsByCustomer[m._id.toString()] || []).length > 0);
        if (!hasActivity) continue;

        // Use first member with payment contact as the primary
        const primary = members.find(m => m.paymentContact?.number)
            || members[0];
        const primaryCid = primary._id.toString();

        // Find existing combined invoice
        const existing = existingInvoices.find(inv =>
            inv.isCombined && inv.carGroupId &&
            inv.carGroupId.toString() === gid);

        // Compute combined total fresh
        let combinedTotal = 0;
        const memberNames = [];
        for (const m of members) {
          const mJobs = jobsByCustomer[m._id.toString()] || [];
          const comp  = await computeCustomerInvoice(m, mJobs, pricing);
          combinedTotal += comp.grandTotal;
          memberNames.push(m.customerName);
        }

        result.push({
          customerId:       primaryCid,
          customerName:     primary.customerName,
          vehicleNumber:    primary.vehicleNumber,
          carModel:         primary.carModel,
          carType:          primary.carType,
          customerPhone:    primary.phone,
          paymentContact:   primary.paymentContact || null,
          hasPaymentContact: !!(primary.paymentContact?.number),
          carGroupId:       customer.carGroupId,
          groupMemberNames: memberNames,
          isGroupCard:      true,
          invoiceId:        existing?._id || null,
          invoiceNumber:    existing?.invoiceNumber || null,
          shared:           existing?.shared || false,
          sharedAt:         existing?.sharedAt || null,
          paymentCollected: existing?.paymentCollected || false,
          collectedAt:      existing?.collectedAt || null,
          grandTotal:       existing?.grandTotal ?? combinedTotal,
          displayTotal:     (existing?.shared || existing?.paymentCollected)
              ? (existing?.grandTotal ?? combinedTotal)
              : combinedTotal,
          discountAmount:   existing?.discountAmount || 0,
          isCombined:       true,
        });
        continue;
      }

      // Individual customer (no group)
      if (jobs.length === 0) continue;

      const computed = await computeCustomerInvoice(customer, jobs, pricing);
      const existing = invoiceByCustomer[cid];
      const hasPaymentContact = !!(customer.paymentContact?.number);

      result.push({
        customerId:       cid,
        customerName:     customer.customerName,
        vehicleNumber:    customer.vehicleNumber,
        carModel:         customer.carModel,
        carType:          customer.carType,
        customerPhone:    customer.phone,
        paymentContact:   customer.paymentContact || null,
        hasPaymentContact,
        carGroupId:       null,
        isGroupCard:      false,
        isCombined:       false,
        ...computed,
        invoiceId:        existing?._id || null,
        invoiceNumber:    existing?.invoiceNumber || null,
        shared:           existing?.shared || false,
        sharedAt:         existing?.sharedAt || null,
        paymentCollected: existing?.paymentCollected || false,
        collectedAt:      existing?.collectedAt || null,
        adjustment:       existing?.adjustment ?? 0,
        lineItems:        existing?.lineItems?.length
            ? existing.lineItems : computed.lineItems,
        grandTotal:       existing?.grandTotal ?? computed.grandTotal,
        computedTotal:    computed.grandTotal,
        displayTotal:     (existing?.shared || existing?.paymentCollected)
            ? (existing?.grandTotal ?? computed.grandTotal)
            : computed.grandTotal,
      });
    }

    res.json({ month, year, customers: result });
  } catch (err) { console.error(err); res.status(500).send('Server error'); }
});

// ── GET /admin/invoice/metrics?month=&year= ───────────────────────────────────
router.get('/invoice/metrics', adminAuth, async (req, res) => {
  try {
    const now   = new Date();
    const ist   = new Date(now.getTime() + 5.5 * 60 * 60 * 1000);
    const month = parseInt(req.query.month) || (ist.getUTCMonth() + 1);
    const year  = parseInt(req.query.year)  || ist.getUTCFullYear();

    const invoices = await Invoice.find({ month, year });

    const totalRevenue   = invoices.reduce((s, i) => s + (i.grandTotal || 0), 0);
    const totalCollected = invoices
      .filter(i => i.paymentCollected)
      .reduce((s, i) => s + (i.grandTotal || 0), 0);
    const totalPending   = Math.round((totalRevenue - totalCollected) * 100) / 100;

    // Per contact breakdown
    const byContact = {};
    for (const inv of invoices) {
      const key  = inv.paymentContact?.number || 'Unknown';
      const name = inv.paymentContact?.name   || 'Unknown';
      if (!byContact[key]) byContact[key] = { name, invoiced: 0, collected: 0 };
      byContact[key].invoiced  += inv.grandTotal || 0;
      if (inv.paymentCollected)
        byContact[key].collected += inv.grandTotal || 0;
    }
    // Round byContact values
    for (const k of Object.keys(byContact)) {
      byContact[k].invoiced  = Math.round(byContact[k].invoiced  * 100) / 100;
      byContact[k].collected = Math.round(byContact[k].collected * 100) / 100;
    }

    res.json({
      month, year,
      totalRevenue:   Math.round(totalRevenue   * 100) / 100,
      totalCollected: Math.round(totalCollected * 100) / 100,
      totalPending,
      byContact: Object.values(byContact),
    });
  } catch (err) { console.error(err); res.status(500).send('Server error'); }
});

// ── GET /admin/invoice/compute/:customerId?month=&year= ───────────────────────
// Returns fresh computed total for a customer — always current, never cached
router.get('/invoice/compute/:customerId', adminAuth, async (req, res) => {
  try {
    const now   = new Date();
    const ist   = new Date(now.getTime() + 5.5 * 60 * 60 * 1000);
    const month = parseInt(req.query.month) || (ist.getUTCMonth() + 1);
    const year  = parseInt(req.query.year)  || ist.getUTCFullYear();

    const customer = await Customer.findById(req.params.customerId);
    if (!customer) return res.status(404).send('Customer not found');

    const configDoc = await Config.findOne({ key: 'invoicePricing' });
    const pricing   = configDoc?.value || {};

    const curMonth = `${year}-${String(month).padStart(2,'0')}`;
    const allJobs  = await Job.find({ customerId: customer._id });
    const jobs     = allJobs.filter(j =>
        j.assignedDate && j.assignedDate.startsWith(curMonth));

    const computed = await computeCustomerInvoice(customer, jobs, pricing);
    res.json({ computedTotal: computed.grandTotal, lineItems: computed.lineItems });
  } catch (err) { console.error(err); res.status(500).send('Server error'); }
});

// ── POST /admin/invoice/generate/:customerId?month=&year= ─────────────────────
// Creates or returns existing invoice for customer for the month
router.post('/invoice/generate/:customerId', adminAuth, async (req, res) => {
  try {
    const now   = new Date();
    const ist   = new Date(now.getTime() + 5.5 * 60 * 60 * 1000);
    const month = parseInt(req.query.month) || (ist.getUTCMonth() + 1);
    const year  = parseInt(req.query.year)  || ist.getUTCFullYear();

    const customer = await Customer.findById(req.params.customerId);
    if (!customer) return res.status(404).send('Customer not found');
    if (!customer.paymentContact?.number)
      return res.status(400).send('Customer has no payment contact set');

    const configDoc = await Config.findOne({ key: 'invoicePricing' });
    const pricing   = configDoc?.value || {};

    const curMonth = `${year}-${String(month).padStart(2,'0')}`;
    const allJobs  = await Job.find({ customerId: customer._id });
    const jobs     = allJobs.filter(j =>
        j.assignedDate && j.assignedDate.startsWith(curMonth));

    const computed = await computeCustomerInvoice(customer, jobs, pricing);

    // Apply adjustment to exterior line item (never to interior)
    const adjustment = parseFloat(req.body?.adjustment ?? 0) || 0;
    let finalLineItems = computed.lineItems.map(i => ({ ...i }));
    let finalTotal     = computed.grandTotal; // already rounded by computeCustomerInvoice
    if (adjustment !== 0) {
      // Find exterior line item by car type label
      const extIdx = finalLineItems.findIndex(i =>
        ['Hatchback','Sedan','SUV'].includes(i.label));
      if (extIdx !== -1) {
        finalLineItems[extIdx].amount = Math.round(
            finalLineItems[extIdx].amount + adjustment);
        finalTotal = finalLineItems.reduce((s, i) => s + i.amount, 0);
      }
    }

    // Check if invoice already exists — update it (regenerate)
    let invoice = await Invoice.findOne({
      customerId: customer._id, month, year });

    if (invoice) {
      invoice.lineItems      = finalLineItems;
      invoice.grandTotal     = finalTotal;
      invoice.attempted      = computed.attempted;
      invoice.cleaned        = computed.cleaned;
      invoice.cancelled      = computed.cancelled;
      invoice.extAttempted   = computed.extAttempted;
      invoice.extCleaned     = computed.extCleaned;
      invoice.extCancelled   = computed.extCancelled;
      invoice.intAttempted   = computed.intAttempted;
      invoice.intCleaned     = computed.intCleaned;
      invoice.intCancelled   = computed.intCancelled;
      invoice.paymentContact = customer.paymentContact;
      invoice.customerName   = customer.customerName;
      invoice.vehicleNumber  = customer.vehicleNumber;
      invoice.carModel       = customer.carModel;
      invoice.carType        = customer.carType;
      invoice.customerPhone  = customer.phone || '';
      invoice.adjustment     = adjustment;
      await invoice.save();
    } else {
      const invoiceNumber = await getNextInvoiceNumber(month, year);
      invoice = await Invoice.create({
        invoiceNumber,
        month, year,
        customerId:    customer._id,
        customerName:  customer.customerName,
        vehicleNumber: customer.vehicleNumber,
        carModel:      customer.carModel,
        carType:       customer.carType,
        customerPhone: customer.phone || '',
        paymentContact: customer.paymentContact,
        attempted:     computed.attempted,
        cleaned:       computed.cleaned,
        cancelled:     computed.cancelled,
        extAttempted:  computed.extAttempted,
        extCleaned:    computed.extCleaned,
        extCancelled:  computed.extCancelled,
        intAttempted:  computed.intAttempted,
        intCleaned:    computed.intCleaned,
        intCancelled:  computed.intCancelled,
        lineItems:     finalLineItems,
        grandTotal:    finalTotal,
        adjustment,
      });
    }

    res.json(invoice);
  } catch (err) { console.error(err); res.status(500).send('Server error'); }
});

// ── PUT /admin/invoice/:invoiceId/mark-shared ─────────────────────────────────
router.put('/invoice/:invoiceId/mark-shared', adminAuth, async (req, res) => {
  try {
    const invoice = await Invoice.findByIdAndUpdate(
      req.params.invoiceId,
      { $set: { shared: true, sharedAt: new Date() } },
      { new: true }
    );
    if (!invoice) return res.status(404).send('Invoice not found');
    res.json(invoice);
  } catch (err) { console.error(err); res.status(500).send('Server error'); }
});

// ── PUT /admin/invoice/:invoiceId/mark-collected ──────────────────────────────
router.put('/invoice/:invoiceId/mark-collected', adminAuth, async (req, res) => {
  try {
    const invoice = await Invoice.findByIdAndUpdate(
      req.params.invoiceId,
      { $set: { paymentCollected: true, collectedAt: new Date() } },
      { new: true }
    );
    if (!invoice) return res.status(404).send('Invoice not found');
    res.json(invoice);
  } catch (err) { console.error(err); res.status(500).send('Server error'); }
});

// ═══════════════════════════════════════════════════════════════════════════
// COMBINED INVOICE
// ═══════════════════════════════════════════════════════════════════════════

// ── PUT /admin/customers/:id/car-group — add/remove from group ───────────────
router.put('/customers/:id/car-group', adminAuth, async (req, res) => {
  try {
    const { action, groupId, memberIds } = req.body;
    console.log(`[car-group] action=${action} customerId=${req.params.id} groupId=${groupId} memberIds=${JSON.stringify(memberIds)}`);

    if (action === 'remove') {
      await Customer.findByIdAndUpdate(req.params.id,
        { $set: { carGroupId: null } });
      console.log(`[car-group] removed ${req.params.id} from group`);

    } else if (action === 'new-group') {
      const newGroupId = new mongoose.Types.ObjectId().toString();
      const allIds = [req.params.id, ...(memberIds || [])];
      const result = await Customer.updateMany(
        { _id: { $in: allIds } },
        { $set: { carGroupId: newGroupId } });
      console.log(`[car-group] created group ${newGroupId} for ${allIds} — modified ${result.modifiedCount}`);

    } else if (action === 'add') {
      if (!groupId) return res.status(400).send('groupId required for add action');
      const result = await Customer.findByIdAndUpdate(req.params.id,
        { $set: { carGroupId: groupId } }, { new: true });
      console.log(`[car-group] added ${req.params.id} to group ${groupId} — result=${result?.carGroupId}`);
    }

    const updated = await Customer.findById(req.params.id);
    console.log(`[car-group] final carGroupId=${updated?.carGroupId}`);
    res.json(updated);
  } catch (err) {
    console.error('[car-group] error:', err);
    res.status(500).send('Server error');
  }
});

// ── GET /admin/car-groups — list all groups with members ──────────────────────
router.get('/car-groups', adminAuth, async (req, res) => {
  try {
    const customers = await Customer.find(
        { carGroupId: { $ne: null } });
    const groups = {};
    for (const c of customers) {
      const g = c.carGroupId;
      if (!groups[g]) groups[g] = [];
      groups[g].push({
        _id: c._id, customerName: c.customerName,
        vehicleNumber: c.vehicleNumber, carModel: c.carModel,
        carType: c.carType, interiorType: c.interiorType,
        paymentContact: c.paymentContact,
      });
    }
    res.json(Object.entries(groups).map(([id, members]) =>
        ({ groupId: id, members })));
  } catch (err) { console.error(err); res.status(500).send('Server error'); }
});

// ── MIGRATION: auto-migrate linkedCustomerId → carGroupId on startup ──────────
// Runs once, safe to call multiple times (idempotent)
(async () => {
  try {
    const linked = await Customer.find({
      linkedCustomerId: { $ne: null }, carGroupId: null });
    for (const custA of linked) {
      const custB = await Customer.findById(custA.linkedCustomerId);
      if (!custB) continue;
      // Only create group if neither has one yet
      if (!custA.carGroupId && !custB.carGroupId) {
        const groupId = new mongoose.Types.ObjectId().toString();
        await Customer.updateMany(
          { _id: { $in: [custA._id, custB._id] } },
          { carGroupId: groupId });
        console.log(`[migration] Created car group ${groupId} for ${custA.customerName} + ${custB.customerName}`);
      }
    }
  } catch (err) { console.error('[migration] car group migration failed:', err); }
})();

// ── GET /admin/invoice/compute-combined/:customerId ───────────────────────────
router.get('/invoice/compute-combined/:customerId', adminAuth, async (req, res) => {
  try {
    const now   = new Date();
    const ist   = new Date(now.getTime() + 5.5 * 60 * 60 * 1000);
    const month = parseInt(req.query.month) || (ist.getUTCMonth() + 1);
    const year  = parseInt(req.query.year)  || ist.getUTCFullYear();

    const cust = await Customer.findById(req.params.customerId);
    if (!cust) return res.status(404).send('Customer not found');
    if (!cust.carGroupId) return res.status(400).send('Customer has no car group');

    const groupMembers = await Customer.find({ carGroupId: cust.carGroupId });
    const configDoc    = await Config.findOne({ key: 'invoicePricing' });
    const pricing      = configDoc?.value || {};
    const curMonth     = `${year}-${String(month).padStart(2,'0')}`;

    const getJobs = async (c) => {
      const all = await Job.find({ customerId: c._id });
      return all.filter(j => j.assignedDate && j.assignedDate.startsWith(curMonth));
    };

    let subtotal = 0;
    const carData = [];
    for (const member of groupMembers) {
      const jobs     = await getJobs(member);
      const computed = await computeCustomerInvoice(member, jobs, pricing);
      subtotal += computed.grandTotal;
      carData.push({ customer: member, computed });
    }

    res.json({ groupId: cust.carGroupId, carData: carData.map(d => ({
      id:   d.customer._id,
      name: d.customer.customerName,
      computed: d.computed,
    })), subtotal });
  } catch (err) { console.error(err); res.status(500).send('Server error'); }
});

// ── POST /admin/invoice/generate-combined/:customerId ─────────────────────────
router.post('/invoice/generate-combined/:customerId', adminAuth, async (req, res) => {
  try {
    const now   = new Date();
    const ist   = new Date(now.getTime() + 5.5 * 60 * 60 * 1000);
    const month = parseInt(req.query.month) || (ist.getUTCMonth() + 1);
    const year  = parseInt(req.query.year)  || ist.getUTCFullYear();

    const { discountFlat = 0, discountPct = 0,
            discountReason = '', adjustment = 0 } = req.body;

    const cust = await Customer.findById(req.params.customerId);
    if (!cust) return res.status(404).send('Customer not found');
    if (!cust.carGroupId) return res.status(400).send('No car group');
    if (!cust.paymentContact?.number)
      return res.status(400).send('Customer has no payment contact');

    const groupMembers = await Customer.find({ carGroupId: cust.carGroupId });
    const configDoc    = await Config.findOne({ key: 'invoicePricing' });
    const pricing      = configDoc?.value || {};
    const curMonth     = `${year}-${String(month).padStart(2,'0')}`;

    const getJobs = async (c) => {
      const all = await Job.find({ customerId: c._id });
      return all.filter(j => j.assignedDate && j.assignedDate.startsWith(curMonth));
    };

    // Compute per-car
    const carResults = [];
    for (const member of groupMembers) {
      const jobs = await getJobs(member);
      const comp = await computeCustomerInvoice(member, jobs, pricing);
      carResults.push({ member, comp });
    }

    // Build line items grouped by car
    const allLineItems = [];
    for (const { member, comp } of carResults) {
      const name = member.customerName.split('-')[0].trim();
      const car  = member.customerName.includes('-')
        ? member.customerName.split('-').slice(1).join('-').trim()
        : member.carModel;
      const carLabel = car ? `${name} — ${car}` : name;
      for (const item of comp.lineItems) {
        allLineItems.push({ ...item, car: carLabel });
      }
    }

    // Apply adjustment to first exterior line item
    const adjAmt = Math.round(adjustment || 0);
    if (adjAmt !== 0) {
      const extIdx = allLineItems.findIndex(i =>
        ['Hatchback','Sedan','SUV'].includes(i.label));
      if (extIdx !== -1) allLineItems[extIdx].amount += adjAmt;
    }

    const rawSubtotal    = carResults.reduce((s, r) => s + r.comp.grandTotal, 0) + adjAmt;
    const pctAmt         = Math.round(rawSubtotal * (discountPct / 100));
    const flatAmt        = Math.round(discountFlat);
    const discountAmount = pctAmt + flatAmt;
    const grandTotal     = rawSubtotal - discountAmount;

    // Build carStats — one entry per car
    const carStats = carResults.map(({ member, comp }) => ({
      customerId:   member._id,
      customerName: member.customerName,
      vehicleNumber:member.vehicleNumber,
      carModel:     member.carModel,
      carType:      member.carType,
      interiorType: member.interiorType || 'None',
      extAttempted: comp.extAttempted,
      extCleaned:   comp.extCleaned,
      extCancelled: comp.extCancelled,
      intAttempted: comp.intAttempted,
      intCleaned:   comp.intCleaned,
      intCancelled: comp.intCancelled,
    }));

    let invoice = await Invoice.findOne({
      customerId: cust._id, month, year, isCombined: true });

    const invoiceData = {
      isCombined:    true,
      carGroupId:    cust.carGroupId,
      lineItems:     allLineItems,
      grandTotal,
      attempted:     carStats.reduce((s, c) => s + c.extAttempted + c.intAttempted, 0),
      cleaned:       carStats.reduce((s, c) => s + c.extCleaned   + c.intCleaned,   0),
      cancelled:     carStats.reduce((s, c) => s + c.extCancelled + c.intCancelled, 0),
      carStats,
      discountFlat:  flatAmt,
      discountPct,
      discountReason,
      discountAmount,
      paymentContact: cust.paymentContact,
      customerName:  cust.customerName,
      vehicleNumber: cust.vehicleNumber,
      carModel:      cust.carModel,
      carType:       cust.carType,
      customerPhone: cust.phone || '',
    };

    if (invoice) {
      Object.assign(invoice, invoiceData);
      await invoice.save();
    } else {
      const invoiceNumber = await getNextInvoiceNumber(month, year);
      invoice = await Invoice.create({
        invoiceNumber, month, year,
        customerId: cust._id, ...invoiceData,
      });
    }

    res.json(invoice);
  } catch (err) { console.error(err); res.status(500).send('Server error'); }
});

// ═══════════════════════════════════════════════════════════════════════════
// SALARY SLIP
// ═══════════════════════════════════════════════════════════════════════════

// ── GET /admin/salary-slip/:employeeId?month=&year= ───────────────────────────
router.get('/salary-slip/:employeeId', adminAuth, async (req, res) => {
  try {
    const ist   = new Date(Date.now() + 5.5 * 60 * 60 * 1000);
    const month = parseInt(req.query.month) || (ist.getUTCMonth() + 1);
    const year  = parseInt(req.query.year)  || ist.getUTCFullYear();

    const slip = await SalarySlip.findOne({
      employeeId: req.params.employeeId, month, year });
    res.json(slip || null);
  } catch (err) {
    console.error('[salary-slip GET]', err);
    res.status(500).send('Server error');
  }
});

// ── POST /admin/salary-slip/:employeeId — create/update salary slip ───────────
router.post('/salary-slip/:employeeId', adminAuth, async (req, res) => {
  try {
    const ist   = new Date(Date.now() + 5.5 * 60 * 60 * 1000);
    const month = parseInt(req.query.month) || (ist.getUTCMonth() + 1);
    const year  = parseInt(req.query.year)  || ist.getUTCFullYear();

    const {
      baseSalary, distanceAllowance, dailyIncentive,
      daysWorked, totalWorkingDays,
      salesIncentive, employeeReferral, bonus, deductions,
      employeeName, employeePhone, joiningDate,
    } = req.body;

    const computedTotal = (baseSalary || 0) +
        (distanceAllowance || 0) + (dailyIncentive || 0);

    const sumItems = (arr) => (arr || []).reduce((s, i) => s + (i.amount || 0), 0);
    const netTotal = computedTotal +
        sumItems(salesIncentive) +
        sumItems(employeeReferral) +
        sumItems(bonus) -
        sumItems(deductions);

    let slip = await SalarySlip.findOne({
      employeeId: req.params.employeeId, month, year });

    const slipData = {
      employeeName, employeePhone, joiningDate,
      baseSalary, distanceAllowance, dailyIncentive,
      daysWorked: daysWorked || 0,
      totalWorkingDays: totalWorkingDays || 0,
      computedTotal, salesIncentive, employeeReferral,
      bonus, deductions, netTotal,
    };

    if (slip) {
      Object.assign(slip, slipData);
      await slip.save();
    } else {
      slip = await SalarySlip.create({
        employeeId: req.params.employeeId,
        month, year, ...slipData,
      });
    }

    // Credit material fund for ₹100 deductions present in slip
    const materialDeduction = (deductions || []).find(d =>
        d.reason && d.reason.toLowerCase().includes('material'));
    if (materialDeduction?.amount) {
      await Fund.findOneAndUpdate(
        { fundType: 'material' },
        { $inc: { balance: materialDeduction.amount } },
        { upsert: true }
      );
    }

    res.json(slip);
  } catch (err) { console.error(err); res.status(500).send('Server error'); }
});

// ── PUT /admin/salary-slip/:slipId/mark-paid ──────────────────────────────────
router.put('/salary-slip/:slipId/mark-paid', adminAuth, async (req, res) => {
  try {
    const slip = await SalarySlip.findByIdAndUpdate(
      req.params.slipId,
      { $set: { paymentStatus: 'Paid', paidAt: new Date() } },
      { new: true }
    );
    if (!slip) return res.status(404).send('Slip not found');
    res.json(slip);
  } catch (err) { console.error(err); res.status(500).send('Server error'); }
});

// ── PUT /admin/salary-slip/:slipId/mark-shared ────────────────────────────────
router.put('/salary-slip/:slipId/mark-shared', adminAuth, async (req, res) => {
  try {
    const slip = await SalarySlip.findByIdAndUpdate(
      req.params.slipId,
      { $set: { shared: true, sharedAt: new Date() } },
      { new: true }
    );
    if (!slip) return res.status(404).send('Slip not found');
    res.json(slip);
  } catch (err) { console.error(err); res.status(500).send('Server error'); }
});

// ═══════════════════════════════════════════════════════════════════════════
// EXPENSES & FUNDS
// ═══════════════════════════════════════════════════════════════════════════

// ── GET /admin/expenses?month=&year= ─────────────────────────────────────────
router.get('/expenses', adminAuth, async (req, res) => {
  try {
    const ist   = new Date(Date.now() + 5.5 * 60 * 60 * 1000);
    const month = parseInt(req.query.month) || (ist.getUTCMonth() + 1);
    const year  = parseInt(req.query.year)  || ist.getUTCFullYear();
    const expenses = await Expense.find({ month, year }).sort({ date: -1 });
    res.json(expenses);
  } catch (err) { console.error(err); res.status(500).send('Server error'); }
});

// ── POST /admin/expenses ──────────────────────────────────────────────────────
router.post('/expenses', adminAuth, async (req, res) => {
  try {
    const { month, year, date, fundType, category, amount, note } = req.body;
    const expense = await Expense.create({
      month, year, date, fundType, category,
      amount: Math.round(amount),
      note: note || '',
    });

    // If top-up — credit the relevant fund
    if (fundType === 'material-topup' || fundType === 'bd-topup') {
      const ft = fundType === 'material-topup' ? 'material' : 'bd';
      await Fund.findOneAndUpdate(
        { fundType: ft },
        { $inc: { balance: Math.round(amount) } },
        { upsert: true }
      );
    }

    // If material/bd spending — debit the fund
    if (fundType === 'material' || fundType === 'bd') {
      await Fund.findOneAndUpdate(
        { fundType },
        { $inc: { balance: -Math.round(amount) } },
        { upsert: true }
      );
    }

    res.json(expense);
  } catch (err) { console.error(err); res.status(500).send('Server error'); }
});

// ── DELETE /admin/expenses/:id ────────────────────────────────────────────────
router.delete('/expenses/:id', adminAuth, async (req, res) => {
  try {
    const expense = await Expense.findById(req.params.id);
    if (!expense) return res.status(404).send('Not found');

    // Reverse the fund effect
    if (expense.fundType === 'material-topup' || expense.fundType === 'bd-topup') {
      const ft = expense.fundType === 'material-topup' ? 'material' : 'bd';
      await Fund.findOneAndUpdate({ fundType: ft },
        { $inc: { balance: -expense.amount } });
    }
    if (expense.fundType === 'material' || expense.fundType === 'bd') {
      await Fund.findOneAndUpdate({ fundType: expense.fundType },
        { $inc: { balance: expense.amount } });
    }

    await Expense.findByIdAndDelete(req.params.id);
    res.json({ deleted: true });
  } catch (err) { console.error(err); res.status(500).send('Server error'); }
});

// ── GET /admin/funds ──────────────────────────────────────────────────────────
router.get('/funds', adminAuth, async (req, res) => {
  try {
    const [material, bd] = await Promise.all([
      Fund.findOne({ fundType: 'material' }),
      Fund.findOne({ fundType: 'bd' }),
    ]);
    res.json({
      material: { balance: material?.balance ?? 0, openingBalance: material?.openingBalance ?? 0 },
      bd:       { balance: bd?.balance ?? 0,       openingBalance: bd?.openingBalance ?? 0 },
    });
  } catch (err) { console.error(err); res.status(500).send('Server error'); }
});

// ── PUT /admin/funds/:fundType/opening ───────────────────────────────────────
// Set opening balance once
router.put('/funds/:fundType/opening', adminAuth, async (req, res) => {
  try {
    const { amount } = req.body;
    const fund = await Fund.findOneAndUpdate(
      { fundType: req.params.fundType },
      { $set: { openingBalance: Math.round(amount), balance: Math.round(amount) } },
      { upsert: true, new: true }
    );
    res.json(fund);
  } catch (err) { console.error(err); res.status(500).send('Server error'); }
});

// ── GET /admin/pl?month=&year= — P&L summary ─────────────────────────────────
router.get('/pl', adminAuth, async (req, res) => {
  try {
    const ist   = new Date(Date.now() + 5.5 * 60 * 60 * 1000);
    const month = parseInt(req.query.month) || (ist.getUTCMonth() + 1);
    const year  = parseInt(req.query.year)  || ist.getUTCFullYear();

    // Revenue from invoices
    const invoices = await Invoice.find({ month, year, isCombined: { $ne: true } });
    const combinedInvoices = await Invoice.find({ month, year, isCombined: true });
    const allInvoices = [...invoices, ...combinedInvoices];

    const totalInvoiced   = allInvoices.reduce((s, i) => s + (i.grandTotal || 0), 0);
    const totalCollected  = allInvoices
        .filter(i => i.paymentCollected)
        .reduce((s, i) => s + (i.grandTotal || 0), 0);
    const totalOutstanding = totalInvoiced - totalCollected;

    // Salary from slips
    const slips = await SalarySlip.find({ month, year });
    const totalSalaryPayable = slips.reduce((s, sl) => s + (sl.netTotal || 0), 0);
    const totalSalaryPaid    = slips
        .filter(sl => sl.paymentStatus === 'Paid')
        .reduce((s, sl) => s + (sl.netTotal || 0), 0);
    const totalSalaryPending = totalSalaryPayable - totalSalaryPaid;

    // Expenses
    const expenses = await Expense.find({ month, year });
    const plExpenses    = expenses.filter(e => e.fundType === 'pl');
    const materialTopups = expenses
        .filter(e => e.fundType === 'material-topup')
        .reduce((s, e) => s + e.amount, 0);
    const bdTopups = expenses
        .filter(e => e.fundType === 'bd-topup')
        .reduce((s, e) => s + e.amount, 0);

    // Group P&L expenses by category
    const byCategory = {};
    for (const e of plExpenses) {
      byCategory[e.category] = (byCategory[e.category] || 0) + e.amount;
    }
    const totalPlExpenses = plExpenses.reduce((s, e) => s + e.amount, 0);

    // Material fund — ₹100 per active employee (from slips with that deduction)
    const materialFromSlips = slips.reduce((s, sl) => {
      const deduction = (sl.deductions || [])
          .find(d => d.reason && d.reason.toLowerCase().includes('material'));
      return s + (deduction?.amount || 0);
    }, 0);

    // Net profit = collected - salary paid - pl expenses - fund topups
    const netProfit = totalCollected - totalSalaryPaid - totalPlExpenses
        - materialTopups - bdTopups;

    res.json({
      month, year,
      revenue: { invoiced: totalInvoiced, collected: totalCollected, outstanding: totalOutstanding },
      salary:  { payable: totalSalaryPayable, paid: totalSalaryPaid, pending: totalSalaryPending },
      fundAllocations: { material: materialTopups, bd: bdTopups, materialFromSlips },
      expensesByCategory: byCategory,
      totalPlExpenses,
      netProfit,
    });
  } catch (err) { console.error(err); res.status(500).send('Server error'); }
});

// ── PUT /admin/customers/:id/active — toggle customer active status ────────────
router.put('/customers/:id/active', adminAuth, async (req, res) => {
  try {
    const { isActive } = req.body;
    const customer = await Customer.findByIdAndUpdate(
      req.params.id,
      { $set: { isActive: !!isActive } },
      { new: true }
    );
    if (!customer) return res.status(404).send('Not found');
    res.json(customer);
  } catch (err) { console.error(err); res.status(500).send('Server error'); }
});

module.exports = router;