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

// ── GET /jobs/employee/:employeeId — today's jobs for an employee ─────────────
router.get('/employee/:employeeId', async (req, res) => {
  try {
    const today = todayIST();
    const jobs  = await Job.find({
      employeeId:   req.params.employeeId,
      assignedDate: today,
    }).populate('customerId').sort({ sortOrder: 1 }); // employee sees jobs in planner order

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

module.exports = router;