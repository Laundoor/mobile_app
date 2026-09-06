const express    = require('express');
const router     = express.Router();
const Job        = require('../models/job');
const User       = require('../models/user');
const Attendance = require('../models/attendance');
const Warehouse  = require('../models/warehouse');

// Returns current date in IST as YYYY-MM-DD
function todayIST() {
  const now = new Date();
  const ist = new Date(now.getTime() + 5.5 * 60 * 60 * 1000);
  return ist.toISOString().split('T')[0];
}

// ── GET /supervisor/team-jobs?date= ──────────────────────────────────────────
// Returns all active employees with their jobs for the date
// Used by supervisor Team tab
router.get('/team-jobs', async (req, res) => {
  try {
    const date = req.query.date || todayIST();

    // All active employees (excluding the requesting supervisor — client filters if needed)
    const employees = await User.find({ isActive: true })
      .select('_id name phone role supervisorId');

    // All jobs for the date
    const jobs = await Job.find({ assignedDate: date })
      .populate('customerId', 'customerName carModel carType vehicleNumber carPhoto location')
      .sort({ sortOrder: 1 });

    // Group jobs by employeeId
    const jobsByEmployee = {};
    for (const job of jobs) {
      const eid = job.employeeId.toString();
      if (!jobsByEmployee[eid]) jobsByEmployee[eid] = [];
      jobsByEmployee[eid].push(job);
    }

    const result = employees.map(emp => {
      const empJobs = jobsByEmployee[emp._id.toString()] || [];
      const total     = empJobs.length;
      const completed = empJobs.filter(j => j.status === 'Completed').length;
      const cancelled = empJobs.filter(j => j.status === 'Cancelled').length;
      const pending   = empJobs.filter(j => j.status === 'Pending' || j.status === 'In Progress').length;

      return {
        employeeId:   emp._id,
        name:         emp.name,
        phone:        emp.phone,
        role:         emp.role,
        supervisorId: emp.supervisorId,
        total, completed, cancelled, pending,
        jobs: empJobs,
      };
    });

    res.json({ date, employees: result });
  } catch (err) {
    console.error(err);
    res.status(500).send("Server error");
  }
});

// ── POST /supervisor/inspect/:jobId ──────────────────────────────────────────
// Supervisor inspects a completed job — adds entry to inspections[]
// Body: { supervisorId, supervisorName, photoUrl }
router.post('/inspect/:jobId', async (req, res) => {
  try {
    const { supervisorId, supervisorName, photoUrl } = req.body;
    if (!supervisorId || !photoUrl)
      return res.status(400).send("supervisorId and photoUrl required");

    const job = await Job.findById(req.params.jobId);
    if (!job) return res.status(404).send("Job not found");
    if (job.status !== 'Completed')
      return res.status(400).json({ code: 'NOT_COMPLETED', message: "Can only inspect completed jobs" });

    // One inspection per supervisor per job
    const alreadyInspected = job.inspections.some(
      i => i.supervisorId.toString() === supervisorId.toString()
    );
    if (alreadyInspected)
      return res.status(400).json({ code: 'ALREADY_INSPECTED', message: "Already inspected by you" });

    job.inspections.push({
      supervisorId,
      supervisorName: supervisorName || 'Supervisor',
      photoUrl,
      inspectedAt: new Date(),
    });
    await job.save();
    res.json(job);
  } catch (err) {
    console.error(err);
    res.status(500).send("Server error");
  }
});

// ── GET /supervisor/warehouses ────────────────────────────────────────────────
// Returns all active warehouses — used by supervisor to pick warehouse for visit
router.get('/warehouses', async (req, res) => {
  try {
    const warehouses = await Warehouse.find({ isActive: true });
    res.json(warehouses);
  } catch (err) {
    res.status(500).send("Server error");
  }
});

// ── POST /supervisor/warehouse-visit ─────────────────────────────────────────
// Records a warehouse visit on the attendance record for today
// Body: { employeeId, warehouseId, photoUrl }
// If no attendance exists yet for today, creates one (triggers attendance requirement on Flutter side)
router.post('/warehouse-visit', async (req, res) => {
  try {
    const { employeeId, warehouseId, photoUrl } = req.body;
    if (!employeeId || !warehouseId || !photoUrl)
      return res.status(400).send("employeeId, warehouseId and photoUrl required");

    const date = todayIST();

    // Check warehouse exists
    const warehouse = await Warehouse.findById(warehouseId);
    if (!warehouse) return res.status(404).send("Warehouse not found");

    // Find or create attendance record for today
    let att = await Attendance.findOne({ employeeId, date });
    if (!att) {
      // No attendance yet — create a minimal record
      // Flutter is responsible for ensuring selfie/towels are submitted first
      att = await Attendance.create({ employeeId, date });
    }

    // One visit per day
    if (att.warehouseVisit?.visitedAt)
      return res.status(400).json({ code: 'ALREADY_VISITED', message: "Warehouse already visited today" });

    att.warehouseVisit = {
      warehouseId,
      photoUrl,
      visitedAt: new Date(),
    };
    await att.save();

    res.json({
      message:       'Warehouse visit recorded',
      visitedAt:     att.warehouseVisit.visitedAt,
      warehouseName: warehouse.name,
      warehouseId,
    });
  } catch (err) {
    console.error(err);
    res.status(500).send("Server error");
  }
});

// ── GET /supervisor/inspection-count/:employeeId?date= ───────────────────────
// Returns today's inspection count for a supervisor — used by incentive check
router.get('/inspection-count/:employeeId', async (req, res) => {
  try {
    const date = req.query.date || todayIST();

    // Count all jobs inspected by this supervisor today
    const jobs = await Job.find({
      assignedDate:         date,
      'inspections.supervisorId': req.params.employeeId,
    });

    const count = jobs.filter(j =>
      j.inspections.some(i => i.supervisorId.toString() === req.params.employeeId)
    ).length;

    res.json({ date, inspectionCount: count });
  } catch (err) {
    res.status(500).send("Server error");
  }
});

module.exports = router;