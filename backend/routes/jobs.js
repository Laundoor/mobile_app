const express  = require('express');
const axios    = require('axios');
const router   = express.Router();
const Job      = require('../models/job');
const Customer = require('../models/customer');
const User     = require('../models/user');

// Returns current date in IST (UTC+5:30) as YYYY-MM-DD
function todayIST() {
  const now = new Date();
  const ist = new Date(now.getTime() + 5.5 * 60 * 60 * 1000);
  return ist.toISOString().split('T')[0];
}

// Full incentive computation — mirrors computeIncentive() in admin.js exactly
// Must stay in sync with admin.js whenever criteria change
async function computeIncentiveFull(record, employeeId, date, pricing) {
  const incentiveAmt = pricing.dailyIncentive ?? 100;
  const isSaturday   = new Date(date + 'T12:00:00Z').getUTCDay() === 6;
  const reasons      = [];

  if (!record)
    return { earned: false, amount: 0, isSaturday, reasons: ['No attendance record'] };
  if (record.incentiveExcused)
    return { earned: true, excused: true, amount: incentiveAmt, isSaturday, reasons: [] };

  if (record.selfieApproval  !== 'approved') reasons.push('selfie');
  if (record.towelsApproval  !== 'approved') reasons.push('towels');
  if (!record.towelSoakUrl)                  reasons.push('towelSoakMissing');
  else if (record.towelSoakApproval !== 'approved') reasons.push('towelSoak');
  if (isSaturday) {
    if (!record.dusterSoakUrl)               reasons.push('dusterSoakMissing');
    else if (record.dusterSoakApproval !== 'approved') reasons.push('dusterSoak');
  }

  // Before photo of first job on or before 06:15 IST
  // If sortOrder:1 job was cancelled (no beforeUploadedAt), use its cancelledAt
  // or fall back to the next job with a beforeUploadedAt
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
    if (hhmm > 6 * 60 + 15) reasons.push('late');
  } else {
    reasons.push('late'); // no timestamp at all
  }

  // Minimum 5 completed cars
  const completedCount = await Job.countDocuments({
    employeeId, assignedDate: date, status: 'Completed' });
  if (completedCount < 5) reasons.push('minCars');

  // No unresolved complaints
  const complainedJob = await Job.findOne({
    employeeId, assignedDate: date,
    'complaint.raised':   true,
    'complaint.resolved': { $ne: true },
  });
  if (complainedJob) reasons.push('complaint');

  return {
    earned:    reasons.length === 0,
    amount:    reasons.length === 0 ? incentiveAmt : 0,
    isSaturday,
    reasons,
  };
}

// Half-down rounding: rounds up only if fraction is strictly > 0.5
// e.g. 28.5 → 28, 28.51 → 29
function halfDownRound(value) {
  return Math.max(0, Math.ceil(value - 0.5));
}

// Haversine fallback
function haversineKm(lat1, lng1, lat2, lng2) {
  const R    = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a    = Math.sin(dLat/2)**2 +
               Math.cos(lat1*Math.PI/180) * Math.cos(lat2*Math.PI/180) *
               Math.sin(dLng/2)**2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
}

// Google Distance Matrix — one API call for whole day route (with haversine fallback)
async function computeDayDistanceKm(points) {
  if (points.length < 2) return 0;
  const apiKey   = process.env.LOCATION_KEY;
  const origins  = points.slice(0, -1);
  const dests    = points.slice(1);

  if (apiKey && origins.length <= 25) {
    try {
      const origStr = origins.map(p => `${p.lat},${p.lng}`).join('|');
      const destStr = dests.map(p => `${p.lat},${p.lng}`).join('|');
      const url = `https://maps.googleapis.com/maps/api/distancematrix/json` +
                  `?origins=${origStr}&destinations=${destStr}` +
                  `&mode=driving&units=metric&key=${apiKey}`;
      const { data } = await axios.get(url, { timeout: 10000 });
      if (data?.status === 'OK') {
        let total = 0;
        for (let i = 0; i < origins.length; i++) {
          const el = data.rows?.[i]?.elements?.[i];
          total += el?.status === 'OK'
            ? el.distance.value / 1000
            : haversineKm(origins[i].lat, origins[i].lng,
                          dests[i].lat,   dests[i].lng);
        }
        return parseFloat(total.toFixed(2));
      }
    } catch (e) { /* fall through to haversine */ }
  }

  // Full haversine fallback
  let total = 0;
  for (let i = 0; i < origins.length; i++)
    total += haversineKm(origins[i].lat, origins[i].lng,
                         dests[i].lat,   dests[i].lng);
  return parseFloat(total.toFixed(2));
}

// ── GET /jobs/employee/:employeeId — jobs for an employee (default: today) ────
router.get('/employee/:employeeId', async (req, res) => {
  try {
    const date = req.query.date || todayIST();
    const jobs  = await Job.find({
      employeeId:   req.params.employeeId,
      assignedDate: date,
    }).populate('customerId').sort({ sortOrder: 1 });
    res.json(jobs);
  } catch (err) {
    res.status(500).send("Server error");
  }
});

// ── GET /jobs/:id — single job with all details ───────────────────────────────
router.get('/:id', async (req, res) => {
  try {
    const job = await Job.findById(req.params.id)
      .populate('customerId')
      .populate('employeeId', 'name email');
    if (!job) return res.status(404).send("Job not found");
    res.json(job);
  } catch (err) {
    res.status(500).send("Server error");
  }
});

// ── POST /jobs — create a job (admin assigns customer to employee) ─────────────
// Body: { customerId, employeeId, serviceType, assignedDate? }
router.post('/', async (req, res) => {
  try {
    const { customerId, employeeId, serviceType, assignedDate } = req.body;

    if (!customerId || !employeeId || !serviceType)
      return res.status(400).send("customerId, employeeId, serviceType required");

    const today = assignedDate || todayIST();

    // Prevent duplicate assignment: same customer, same employee, same day
    const duplicate = await Job.findOne({
      customerId,
      employeeId,
      assignedDate: today,
    });
    if (duplicate)
      return res.status(400).send("This customer is already assigned to this employee today");

    // Prevent assigning same customer to multiple employees on same day
    const alreadyAssigned = await Job.findOne({
      customerId,
      assignedDate: today,
      status: { $nin: ['Cancelled'] },
    });
    if (alreadyAssigned)
      return res.status(400).send("Customer already assigned to another employee today");

    const job = await Job.create({
      customerId,
      employeeId,
      serviceType,
      assignedDate: today,
      status: 'Pending',
    });

    const populated = await Job.findById(job._id).populate('customerId');
    res.json(populated);
  } catch (err) {
    console.error(err);
    res.status(500).send("Server error");
  }
});

// ── PUT /jobs/:id/status — update job status ──────────────────────────────────
router.put('/:id/status', async (req, res) => {
  try {
    const { status } = req.body;
    const job = await Job.findById(req.params.id);
    if (!job) return res.status(404).send("Job not found");

    // Block completion of interior jobs unless all 8 after photos uploaded
    if (status === 'Completed') {
      const isInterior = job.serviceType === 'Interior Standard' ||
                         job.serviceType === 'Interior Premium';
      if (isInterior && job.images.interiorAfter.length < 8) {
        return res.status(400).send(
          `Interior job requires 8 after photos. Only ${job.images.interiorAfter.length} uploaded.`
        );
      }
    }

    job.status = status;

    // On completion: monthly count reset if new month, then increment + snapshot
    if (status === 'Completed') {
      job.completedAt = new Date();
      const nowIST   = new Date(job.completedAt.getTime() + 5.5 * 60 * 60 * 1000);
      const curMonth = `${nowIST.getUTCFullYear()}-${String(nowIST.getUTCMonth() + 1).padStart(2, '0')}`;

      const existing = await Customer.findById(job.customerId);
      const needsReset = existing?.lastServiceMonth !== curMonth;

      const customer = await Customer.findByIdAndUpdate(
        job.customerId,
        needsReset
          ? { $set: { serviceCount: 1, lastServiceMonth: curMonth } }
          : { $inc: { serviceCount: 1 }, $set: { lastServiceMonth: curMonth } },
        { new: true }
      );
      job.serviceCount = customer.serviceCount;

      // If this is a reassigned job, auto-resolve the original complaint
      if (job.originalJobId) {
        const originalJob = await Job.findById(job.originalJobId)
            .populate('employeeId', 'name');
        // Get new employee name for resolvedBy
        const newEmp = await User.findById(job.employeeId).select('name');
        if (originalJob?.complaint?.raised && !originalJob.complaint?.resolved) {
          await Job.findByIdAndUpdate(job.originalJobId, {
            'complaint.resolved':   true,
            'complaint.resolvedAt': new Date(),
            'complaint.resolvedBy': newEmp?.name || 'Unknown',
          });
        }
      }
    }

    await job.save();
    res.json(job);
  } catch (err) {
    res.status(500).send("Server error");
  }
});

// ── PUT /jobs/:id/cancel — cancel job with photo URL ─────────────────────────
// Body: { cancelPhotoUrl, cancelReason }
router.put('/:id/cancel', async (req, res) => {
  try {
    const { cancelPhotoUrl, cancelReason } = req.body;
    const job = await Job.findById(req.params.id);
    if (!job) return res.status(404).send("Job not found");

    job.status         = 'Cancelled';
    job.cancelledAt    = new Date();
    job.cancelPhotoUrl = cancelPhotoUrl || null;
    job.cancelReason   = cancelReason   || null;
    await job.save();
    res.json(job);
  } catch (err) {
    res.status(500).send("Server error");
  }
});

// ── GET /jobs/day-summary/:employeeId — summary for today ─────────────────────
router.get('/day-summary/:employeeId', async (req, res) => {
  try {
    const today = todayIST();
    const jobs  = await Job.find({
      employeeId:   req.params.employeeId,
      assignedDate: today,
    }).populate('customerId');

    const total     = jobs.length;
    const completed = jobs.filter(j => j.status === 'Completed').length;
    const cancelled = jobs.filter(j => j.status === 'Cancelled').length;

    // Distance: Google Distance Matrix API (driving), fallback to haversine
    const emp  = await User.findById(req.params.employeeId);

    let distanceKm = 0;
    if (emp?.homeLocation?.lat) {
      const home = emp.homeLocation;

      const doneJobs = jobs
        .filter(j =>
          (j.status === 'Completed' || j.status === 'Cancelled') &&
          j.customerId?.location?.lat
        )
        .sort((a, b) => (a.sortOrder || 0) - (b.sortOrder || 0));

      if (doneJobs.length > 0) {
        const waypoints   = doneJobs.map(j => ({
          lat: j.customerId.location.lat,
          lng: j.customerId.location.lng,
        }));
        const routePoints = [home, ...waypoints, home];
        const apiKey      = process.env.LOCATION_KEY;

        if (apiKey && routePoints.length <= 26) {
          try {
            const origins  = routePoints.slice(0, -1);
            const dests    = routePoints.slice(1);
            const origStr  = origins.map(p => `${p.lat},${p.lng}`).join('|');
            const destStr  = dests.map(p => `${p.lat},${p.lng}`).join('|');
            const url = `https://maps.googleapis.com/maps/api/distancematrix/json` +
                        `?origins=${origStr}&destinations=${destStr}` +
                        `&mode=driving&units=metric&key=${apiKey}`;
            const { data } = await axios.get(url, { timeout: 10000 });

            if (data?.status === 'OK') {
              for (let i = 0; i < origins.length; i++) {
                const el = data.rows?.[i]?.elements?.[i];
                if (el?.status === 'OK') {
                  distanceKm += el.distance.value / 1000;
                } else {
                  // haversine fallback for this leg
                  const o = origins[i], d = dests[i];
                  const dLat = (d.lat - o.lat) * Math.PI / 180;
                  const dLng = (d.lng - o.lng) * Math.PI / 180;
                  const a = Math.sin(dLat/2)**2 +
                    Math.cos(o.lat*Math.PI/180) * Math.cos(d.lat*Math.PI/180) *
                    Math.sin(dLng/2)**2;
                  distanceKm += 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
                }
              }
            } else {
              throw new Error(data?.status);
            }
          } catch (err) {
            console.warn('[day-summary] Google Distance fallback:', err.message);
            // Full haversine fallback
            let prev = home;
            for (const wp of waypoints) {
              const dLat = (wp.lat - prev.lat) * Math.PI / 180;
              const dLng = (wp.lng - prev.lng) * Math.PI / 180;
              const a = Math.sin(dLat/2)**2 +
                Math.cos(prev.lat*Math.PI/180) * Math.cos(wp.lat*Math.PI/180) *
                Math.sin(dLng/2)**2;
              distanceKm += 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
              prev = wp;
            }
            const dLat = (home.lat - prev.lat) * Math.PI / 180;
            const dLng = (home.lng - prev.lng) * Math.PI / 180;
            const a = Math.sin(dLat/2)**2 +
              Math.cos(prev.lat*Math.PI/180) * Math.cos(home.lat*Math.PI/180) *
              Math.sin(dLng/2)**2;
            distanceKm += 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
          }
        } else {
          // No API key — haversine
          let prev = home;
          for (const wp of waypoints) {
            const dLat = (wp.lat - prev.lat) * Math.PI / 180;
            const dLng = (wp.lng - prev.lng) * Math.PI / 180;
            const a = Math.sin(dLat/2)**2 +
              Math.cos(prev.lat*Math.PI/180) * Math.cos(wp.lat*Math.PI/180) *
              Math.sin(dLng/2)**2;
            distanceKm += 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
            prev = wp;
          }
          const dLat = (home.lat - prev.lat) * Math.PI / 180;
          const dLng = (home.lng - prev.lng) * Math.PI / 180;
          const a = Math.sin(dLat/2)**2 +
            Math.cos(prev.lat*Math.PI/180) * Math.cos(home.lat*Math.PI/180) *
            Math.sin(dLng/2)**2;
          distanceKm += 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
        }
      }
    }

    // Hours worked: first job's beforeUploadedAt or cancelledAt → last job's completedAt or cancelledAt
    const startTimes = jobs
      .map(j => j.beforeUploadedAt || j.cancelledAt)
      .filter(Boolean)
      .map(d => new Date(d).getTime());

    const endTimes = jobs
      .map(j => j.completedAt || j.cancelledAt)
      .filter(Boolean)
      .map(d => new Date(d).getTime());

    let hoursWorked = 0;
    if (startTimes.length > 0 && endTimes.length > 0) {
      const firstTime = Math.min(...startTimes);
      const lastTime  = Math.max(...endTimes);
      hoursWorked = (lastTime - firstTime) / (1000 * 60 * 60);
    }

    res.json({
      total,
      completed,
      cancelled,
      distanceKm:  Math.round(distanceKm * 10) / 10,
      hoursWorked: Math.round(hoursWorked * 10) / 10,
    });
  } catch (err) {
    console.error(err);
    res.status(500).send("Server error");
  }
});


router.put('/:id/reassign', async (req, res) => {
  try {
    const { newEmployeeId } = req.body;
    const job = await Job.findByIdAndUpdate(
      req.params.id,
      { employeeId: newEmployeeId, status: 'Pending' },
      { new: true }
    ).populate('customerId');
    res.json(job);
  } catch (err) {
    res.status(500).send("Server error");
  }
});

// ── DELETE /jobs/:id ──────────────────────────────────────────────────────────
router.delete('/:id', async (req, res) => {
  try {
    await Job.findByIdAndDelete(req.params.id);
    res.send("Deleted");
  } catch (err) {
    res.status(500).send("Server error");
  }
});

// ── GET /jobs/my-salary/:employeeId?month=&year= ─────────────────────────────
// Employee-facing salary: per-day earnings + car type breakdown + distance
router.get('/my-salary/:employeeId', async (req, res) => {
  try {
    const now   = new Date();
    const month = parseInt(req.query.month) || (now.getMonth() + 1);
    const year  = parseInt(req.query.year)  || now.getFullYear();
    const from  = new Date(year, month - 1, 1);
    const to    = new Date(year, month, 1);

    const Config    = require('../models/config');
    const configDoc = await Config.findOne({ key: 'pricing' });
    const pricing   = configDoc ? configDoc.value : {
      exterior: { Hatchback: 20, Sedan: 25, SUV: 30 },
      interiorStandard: 40, interiorPremium: 60,
      distancePerKm: 2, dailyIncentive: 100,
    };

    // Fetch employee for home location
    const emp = await User.findById(req.params.employeeId).select('homeLocation');
    const home = emp?.homeLocation?.lat ? emp.homeLocation : null;

    // Completed + cancelled jobs this month (need cancelled for distance)
    const allJobs = await Job.find({
      employeeId: req.params.employeeId,
      status:     { $in: ['Completed', 'Cancelled'] },
      $or: [
        { completedAt: { $gte: from, $lt: to } },
        { cancelledAt: { $gte: from, $lt: to } },
      ],
    }).populate('customerId', 'carType location mapsLink');

    // Group by IST date using completedAt or cancelledAt
    const byDate = {};
    for (const job of allJobs) {
      const ts  = job.completedAt || job.cancelledAt;
      if (!ts) continue;
      const ist = new Date(ts.getTime() + 5.5 * 60 * 60 * 1000);
      const dk  = ist.toISOString().split('T')[0];
      if (!byDate[dk]) byDate[dk] = [];
      byDate[dk].push(job);
    }

    // Attendance records for incentive check
    const Attendance = require('../models/attendance');
    const pad = n => String(n).padStart(2, '0');
    const attRecords = await Attendance.find({
      employeeId: req.params.employeeId,
      date: {
        $gte: `${year}-${pad(month)}-01`,
        $lte: `${year}-${pad(month)}-${pad(new Date(year, month, 0).getDate())}`,
      },
    });
    const attMap = {};
    for (const r of attRecords) attMap[r.date] = r;

    let totalEarnings  = 0;
    let totalIncentive = 0;
    let totalDistanceKm= 0;
    let totalDistanceEarnings = 0;
    const days = [];

    const sortedDates = Object.entries(byDate).sort();

    // Same rule as admin salary: unresolved complaints = not payable
    const isPayable = (job) =>
      job.status === 'Completed' &&
      (!job.complaint?.raised || job.complaint?.resolved === true);

    // ── Step 1: compute job earnings + car counts synchronously (no I/O) ──────
    const dayData = sortedDates.map(([date, dayJobs]) => {
      const completedJobs = dayJobs.filter(j => j.status === 'Completed');
      let dayEarnings = 0;
      const counts = { Hatchback: 0, Sedan: 0, SUV: 0 };
      for (const job of completedJobs) {
        // Skip jobs with unresolved complaints — same logic as admin salary
        if (!isPayable(job)) continue;
        const carType = job.customerId?.carType || 'Hatchback';
        const svcType = job.serviceType || '';
        let earn = 0;
        if (svcType === 'Exterior')
          earn = pricing.exterior?.[carType] ?? 20;
        else if (svcType === 'Interior Standard')
          earn = pricing.interiorStandard ?? 40;
        else if (svcType === 'Interior Premium')
          earn = pricing.interiorPremium ?? 60;
        dayEarnings += earn;
        if (counts[carType] !== undefined) counts[carType]++;
        else counts['Hatchback']++;
      }

      // Build route points — payable completed + cancelled jobs
      let routePoints = null;
      if (home) {
        const sorted = dayJobs
          .filter(j =>
            ((j.status === 'Completed' && isPayable(j)) ||
              j.status === 'Cancelled') &&
            j.customerId?.location?.lat)
          .sort((a, b) => (a.sortOrder || 0) - (b.sortOrder || 0));
        if (sorted.length > 0) {
          const waypoints = sorted.map(j => ({
            lat: j.customerId.location.lat,
            lng: j.customerId.location.lng,
          }));
          routePoints = [home, ...waypoints, home];
        }
      }

      return { date, dayJobs, completedJobs, dayEarnings, counts, routePoints };
    });

    // Helper: is the day fully complete — safe to cache distance
    const isDayComplete = (date) => {
      const r = attMap[date];
      if (!r) return false;
      const isSat = new Date(date + 'T12:00:00Z').getUTCDay() === 6;
      return isSat
        ? !!(r.towelSoakUrl && r.dusterSoakUrl)
        : !!r.towelSoakUrl;
    };

    // ── Step 2: distance — cache-first, API only when needed ─────────────────
    const distanceResults = await Promise.all(
      dayData.map(async d => {
        if (!d.routePoints) return 0;
        const rec    = attMap[d.date];
        const cached = rec?.distanceKm;
        // Use cached value if day is complete and cache exists
        if (isDayComplete(d.date) && cached != null) return cached;
        // Call Google API
        const dayKm = await computeDayDistanceKm(d.routePoints);
        // Write cache if day is complete
        if (isDayComplete(d.date) && rec) {
          await Attendance.findByIdAndUpdate(rec._id,
            { $set: { distanceKm: parseFloat(dayKm.toFixed(2)) } });
        }
        return dayKm;
      })
    );

    // ── Step 3: assemble final response ─────────────────────────────────────
    for (let i = 0; i < dayData.length; i++) {
      const { date, completedJobs, dayEarnings, counts } = dayData[i];
      const dayKm = distanceResults[i];
      const dayDistEarnings = halfDownRound(
          dayKm * (pricing.distancePerKm ?? 2));

      // Full incentive check — same criteria as admin salary
      const record = attMap[date];
      const inc    = await computeIncentiveFull(
          record, req.params.employeeId, date, pricing);
      const incAmt = inc.amount;

      totalEarnings         += dayEarnings;
      totalIncentive        += incAmt;
      totalDistanceKm       += dayKm;
      totalDistanceEarnings += dayDistEarnings;

      days.push({
        date,
        jobCount:         completedJobs.filter(isPayable).length,
        carCounts:        counts,
        earnings:         dayEarnings,
        distanceKm:       parseFloat(dayKm.toFixed(2)),
        distanceEarnings: dayDistEarnings,
        incentive:        incAmt,
        dayTotal:         halfDownRound(dayEarnings + dayDistEarnings + incAmt),
      });
    }

    res.json({
      month, year,
      totalEarnings:         totalEarnings,
      totalDistanceKm:       parseFloat(totalDistanceKm.toFixed(2)),
      totalDistanceEarnings: halfDownRound(totalDistanceEarnings),
      totalIncentive:        totalIncentive,
      grandTotal:            halfDownRound(totalEarnings + totalDistanceEarnings + totalIncentive),
      hasHomeLocation: !!home,
      days,
    });
  } catch (err) { console.error(err); res.status(500).send("Server error"); }
});

// ── GET /jobs/my-complaints/:employeeId?month=&year= ─────────────────────────
// Employee-facing — no auth required (employee uses their own ID)
router.get('/my-complaints/:employeeId', async (req, res) => {
  try {
    const now   = new Date();
    const month = parseInt(req.query.month) || (now.getMonth() + 1);
    const year  = parseInt(req.query.year)  || now.getFullYear();
    const from  = new Date(year, month - 1, 1);
    const to    = new Date(year, month, 1);

    const jobs = await Job.find({
      employeeId:           req.params.employeeId,
      'complaint.raised':   true,
      'complaint.raisedAt': { $gte: from, $lt: to },
    }).populate('customerId', 'customerName carType carModel vehicleNumber carPhoto')
      .sort({ 'complaint.raisedAt': -1 });

    const result = jobs.map(j => ({
      jobId:        j._id,
      assignedDate: j.assignedDate,
      customerName: j.customerId?.customerName || '',
      carType:      j.customerId?.carType      || '',
      carModel:     j.customerId?.carModel     || '',
      vehicleNo:    j.customerId?.vehicleNumber || '',
      carPhoto:     j.customerId?.carPhoto     || null,
      serviceType:  j.serviceType,
      reason:       j.complaint.reason,
      note:         j.complaint.note,
      raisedAt:     j.complaint.raisedAt,
      resolved:     j.complaint.resolved,
      resolvedAt:   j.complaint.resolvedAt,
      resolvedBy:   j.complaint.resolvedBy || null,
    }));

    res.json({
      month, year,
      total:    result.length,
      resolved: result.filter(r => r.resolved).length,
      complaints: result,
    });
  } catch (err) { console.error(err); res.status(500).send("Server error"); }
});

// ── GET /jobs/incentive-history/:employeeId?month=&year= ─────────────────────
// Employee-facing — returns per-day incentive status for the month
router.get('/incentive-history/:employeeId', async (req, res) => {
  try {
    const now   = new Date();
    const month = parseInt(req.query.month) || (now.getMonth() + 1);
    const year  = parseInt(req.query.year)  || now.getFullYear();

    // Build date range as YYYY-MM-DD strings (IST)
    const daysInMonth = new Date(year, month, 0).getDate();
    const pad  = n => String(n).padLeft ? String(n).padStart(2, '0') : (n < 10 ? '0'+n : ''+n);
    const dates = Array.from({ length: daysInMonth }, (_, i) =>
      `${year}-${pad(month)}-${pad(i + 1)}`
    );

    const Attendance = require('../models/attendance');
    const Config     = require('../models/config');
    const configDoc  = await Config.findOne({ key: 'pricing' });
    const pricing    = configDoc ? configDoc.value : { dailyIncentive: 100 };

    // Fetch all attendance records for this employee this month
    const records = await Attendance.find({
      employeeId: req.params.employeeId,
      date: { $gte: `${year}-${pad(month)}-01`,
               $lte: `${year}-${pad(month)}-${pad(daysInMonth)}` },
    });
    const recordMap = {};
    for (const r of records) recordMap[r.date] = r;

    // Only compute for dates that have an attendance record
    const days = [];
    // Run all days in parallel for speed
    const dayResults = await Promise.all(
      dates
        .filter(date => recordMap[date]) // skip days with no attendance
        .map(async date => {
          const record = recordMap[date];
          const inc    = await computeIncentiveFull(
              record, req.params.employeeId, date, pricing);
          return {
            date,
            earned:    inc.earned,
            excused:   inc.excused || false,
            amount:    inc.amount,
            reasons:   inc.reasons,
            isSaturday:inc.isSaturday,
          };
        })
    );
    days.push(...dayResults);

    const totalEarned = days.filter(d => d.earned).reduce((s, d) => s + d.amount, 0);
    const earnedDays  = days.filter(d => d.earned).length;
    const missedDays  = days.filter(d => !d.earned).length;

    res.json({ month, year, totalEarned, earnedDays, missedDays, days });
  } catch (err) { console.error(err); res.status(500).send("Server error"); }
});

module.exports = router;