const express  = require('express');
const router   = express.Router();
const Job      = require('../models/job');
const Customer = require('../models/customer');
const User     = require('../models/user');

// ── GET /jobs/employee/:employeeId — today's jobs for an employee ─────────────
router.get('/employee/:employeeId', async (req, res) => {
  try {
    const today = new Date().toISOString().split('T')[0];
    const jobs  = await Job.find({
      employeeId:   req.params.employeeId,
      assignedDate: today,
    }).populate('customerId'); // attach full customer details

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

    const today = assignedDate || new Date().toISOString().split('T')[0];

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

// ── PUT /jobs/:id/reassign — reassign job to different employee ───────────────
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