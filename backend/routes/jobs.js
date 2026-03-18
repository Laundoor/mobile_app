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

    job.status = status;

    // On completion: increment customer service count + snapshot it on job
    if (status === 'Completed') {
      job.completedAt = new Date();
      const customer = await Customer.findByIdAndUpdate(
        job.customerId,
        { $inc: { serviceCount: 1 } },
        { new: true }
      );
      job.serviceCount = customer.serviceCount;
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
// Employee-facing salary: per-day earnings + car type breakdown, no customer names
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

    const jobs = await Job.find({
      employeeId:  req.params.employeeId,
      status:      'Completed',
      completedAt: { $gte: from, $lt: to },
    }).populate('customerId', 'carType');

    // Group by IST date
    const byDate = {};
    for (const job of jobs) {
      const ist = new Date(job.completedAt.getTime() + 5.5 * 60 * 60 * 1000);
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
    const days = [];

    for (const [date, dayJobs] of Object.entries(byDate).sort()) {
      let dayEarnings = 0;
      const counts = { Hatchback: 0, Sedan: 0, SUV: 0 };

      for (const job of dayJobs) {
        const carType = job.customerId?.carType || 'Hatchback';
        const svcType = job.serviceType || '';
        let   earn    = 0;
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

      // Incentive for this day
      const record = attMap[date];
      let   incAmt = 0;
      if (record) {
        if (record.incentiveExcused) {
          incAmt = pricing.dailyIncentive ?? 100;
        } else {
          const ok = record.selfieApproval  === 'approved' &&
                     record.towelsApproval  === 'approved' &&
                     record.towelSoakApproval === 'approved';
          if (ok) incAmt = pricing.dailyIncentive ?? 100;
        }
      }

      totalEarnings  += dayEarnings;
      totalIncentive += incAmt;
      days.push({
        date,
        jobCount:  dayJobs.length,
        carCounts: counts,
        earnings:  parseFloat(dayEarnings.toFixed(2)),
        incentive: incAmt,
        dayTotal:  parseFloat((dayEarnings + incAmt).toFixed(2)),
      });
    }

    res.json({
      month, year,
      totalEarnings:  parseFloat(totalEarnings.toFixed(2)),
      totalIncentive: parseFloat(totalIncentive.toFixed(2)),
      grandTotal:     parseFloat((totalEarnings + totalIncentive).toFixed(2)),
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
    for (const date of dates) {
      const record = recordMap[date];
      if (!record) continue; // no attendance = no work = skip

      // Inline incentive check (mirrors computeIncentive in admin.js)
      const isSaturday = new Date(date + 'T00:00:00+05:30').getDay() === 6;
      const reasons    = [];

      if (record.incentiveExcused) {
        days.push({ date, earned: true, excused: true,
            amount: pricing.dailyIncentive ?? 100, reasons: [], isSaturday });
        continue;
      }

      if (record.selfieApproval  !== 'approved') reasons.push('selfie');
      if (record.towelsApproval  !== 'approved') reasons.push('towels');
      if (!record.towelSoakUrl)                  reasons.push('towelSoakMissing');
      else if (record.towelSoakApproval !== 'approved') reasons.push('towelSoak');
      if (isSaturday) {
        if (!record.dusterSoakUrl)               reasons.push('dusterSoakMissing');
        else if (record.dusterSoakApproval !== 'approved') reasons.push('dusterSoak');
      }

      // Check first job before time
      const firstJob = await Job.findOne({
        employeeId:   req.params.employeeId,
        assignedDate: date,
      }).sort({ sortOrder: 1 });

      if (firstJob?.beforeUploadedAt) {
        const ist  = new Date(firstJob.beforeUploadedAt.getTime() + 5.5 * 60 * 60 * 1000);
        const hhmm = ist.getHours() * 60 + ist.getMinutes();
        if (hhmm > 6 * 60 + 15) reasons.push('late');
      } else {
        reasons.push('late');
      }

      const complainedJob = await Job.findOne({
        employeeId:           req.params.employeeId,
        assignedDate:         date,
        'complaint.raised':   true,
      });
      if (complainedJob) reasons.push('complaint');

      days.push({
        date,
        earned:     reasons.length === 0,
        excused:    false,
        amount:     reasons.length === 0 ? (pricing.dailyIncentive ?? 100) : 0,
        reasons,
        isSaturday,
      });
    }

    const totalEarned = days.filter(d => d.earned).reduce((s, d) => s + d.amount, 0);
    const earnedDays  = days.filter(d => d.earned).length;
    const missedDays  = days.filter(d => !d.earned).length;

    res.json({ month, year, totalEarned, earnedDays, missedDays, days });
  } catch (err) { console.error(err); res.status(500).send("Server error"); }
});

module.exports = router;