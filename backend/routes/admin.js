const express    = require('express');
const Attendance = require('../models/attendance');

const router   = express.Router();
const User     = require('../models/user');
const Customer = require('../models/customer');
const Job      = require('../models/job');
const Config   = require('../models/config');
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
      .sort({ assignedDate: -1 })
      .populate('employeeId', 'name email');

    // Compute this month's service count (completed, non-cancelled)
    const now   = new Date();
    const from  = new Date(now.getFullYear(), now.getMonth(), 1);
    const to    = new Date(now.getFullYear(), now.getMonth() + 1, 1);
    const monthlyCount = jobs.filter(j =>
      j.status === 'Completed' &&
      j.completedAt && j.completedAt >= from && j.completedAt < to
    ).length;

    res.json({ jobs, monthlyCount });
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
    const isPayable = (job) =>
      job.status === 'Completed' &&
      (!job.complaint?.raised || job.complaint?.resolved === true);

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

    // Helper: is the day fully complete (towel soak done — route won't change)
    const isDayComplete = (date) => {
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
  const firstJob = await Job.findOne({ employeeId, assignedDate: date })
    .sort({ sortOrder: 1 });
  if (firstJob?.beforeUploadedAt) {
    const ist   = new Date(firstJob.beforeUploadedAt.getTime() + 5.5 * 60 * 60 * 1000);
    const hhmm  = ist.getHours() * 60 + ist.getMinutes();
    if (hhmm > 6 * 60 + 15) reasons.push('late'); // after 06:15
  } else {
    reasons.push('late'); // no before photo at all
  }

  // 6. Minimum 5 completed cars for the day
  const completedCount = await Job.countDocuments({
    employeeId,
    assignedDate: date,
    status: 'Completed',
  });
  if (completedCount < 5) reasons.push('minCars');

  // 7. No unresolved complaints raised that day
  const complainedJob = await Job.findOne({
    employeeId,
    assignedDate: date,
    'complaint.raised':    true,
    'complaint.resolved':  { $ne: true }, // resolved complaints don't affect incentive
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

module.exports = router;