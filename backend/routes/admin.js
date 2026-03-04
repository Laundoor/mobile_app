const express  = require('express');
const router   = express.Router();
const User     = require('../models/user');
const Customer = require('../models/customer');
const Job      = require('../models/job');
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

// ═══════════════════════════════════════════════════════════════════════════════
// DASHBOARD
// ═══════════════════════════════════════════════════════════════════════════════

// GET /admin/dashboard
router.get('/dashboard', adminAuth, async (req, res) => {
  try {
    const today     = new Date().toISOString().split('T')[0];
    const employees = await User.find({ role: 'employee' }).select('-password');
    const allJobs   = await Job.find({ assignedDate: today });

    const data = employees.map(emp => {
      const empJobs      = allJobs.filter(j => j.employeeId.toString() === emp._id.toString());
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
  } catch (err) {
    res.status(500).send("Server error");
  }
});

// ═══════════════════════════════════════════════════════════════════════════════
// EMPLOYEE MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

// POST /admin/employees
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
  } catch (err) {
    res.status(500).send("Server error");
  }
});

// GET /admin/employees
router.get('/employees', adminAuth, async (req, res) => {
  try {
    const today     = new Date().toISOString().split('T')[0];
    const employees = await User.find({ role: 'employee' }).select('-password');
    const allJobs   = await Job.find({ assignedDate: today });

    const result = employees.map(emp => {
      const empJobs = allJobs.filter(j => j.employeeId.toString() === emp._id.toString());
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
  } catch (err) {
    res.status(500).send("Server error");
  }
});

// GET /admin/employees/:id
router.get('/employees/:id', adminAuth, async (req, res) => {
  try {
    const emp = await User.findById(req.params.id).select('-password');
    if (!emp) return res.status(404).send("Employee not found");

    const today = new Date().toISOString().split('T')[0];
    const jobs  = await Job.find({
      employeeId:   req.params.id,
      assignedDate: today,
    }).populate('customerId');

    res.json({ employee: emp, jobs });
  } catch (err) {
    res.status(500).send("Server error");
  }
});

// DELETE /admin/employees/:id
router.delete('/employees/:id', adminAuth, async (req, res) => {
  try {
    await User.findByIdAndDelete(req.params.id);
    res.send("Deleted");
  } catch (err) {
    res.status(500).send("Server error");
  }
});

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOMER MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

// POST /admin/customers
router.post('/customers', adminAuth, async (req, res) => {
  try {
    const {
      customerName, address, vehicleNumber,
      vehicleColor, carModel, carType, phone
    } = req.body;
    if (!customerName) return res.status(400).send("customerName required");

    const customer = await Customer.create({
      customerName, address, vehicleNumber,
      vehicleColor, carModel, carType, phone
    });
    res.json(customer);
  } catch (err) {
    res.status(500).send("Server error");
  }
});

// GET /admin/customers
router.get('/customers', adminAuth, async (req, res) => {
  try {
    const customers = await Customer.find().sort({ createdAt: -1 });
    res.json(customers);
  } catch (err) {
    res.status(500).send("Server error");
  }
});

// GET /admin/customers/:id
router.get('/customers/:id', adminAuth, async (req, res) => {
  try {
    const customer = await Customer.findById(req.params.id);
    if (!customer) return res.status(404).send("Not found");
    res.json(customer);
  } catch (err) {
    res.status(500).send("Server error");
  }
});

// GET /admin/customers/:id/history
router.get('/customers/:id/history', adminAuth, async (req, res) => {
  try {
    const jobs = await Job.find({ customerId: req.params.id })
      .sort({ createdAt: -1 })
      .populate('employeeId', 'name email');
    res.json(jobs);
  } catch (err) {
    res.status(500).send("Server error");
  }
});

// PUT /admin/customers/:id
router.put('/customers/:id', adminAuth, async (req, res) => {
  try {
    const customer = await Customer.findByIdAndUpdate(
      req.params.id, req.body, { new: true }
    );
    res.json(customer);
  } catch (err) {
    res.status(500).send("Server error");
  }
});

// DELETE /admin/customers/:id
router.delete('/customers/:id', adminAuth, async (req, res) => {
  try {
    await Customer.findByIdAndDelete(req.params.id);
    res.send("Deleted");
  } catch (err) {
    res.status(500).send("Server error");
  }
});

// ═══════════════════════════════════════════════════════════════════════════════
// JOB ASSIGNMENT
// ═══════════════════════════════════════════════════════════════════════════════

// POST /admin/assign
// Body: { customerId, employeeId, serviceType, assignedDate? }
router.post('/assign', adminAuth, async (req, res) => {
  try {
    const { customerId, employeeId, serviceType, assignedDate } = req.body;
    if (!customerId || !employeeId || !serviceType)
      return res.status(400).send("customerId, employeeId, serviceType required");

    const today = assignedDate || new Date().toISOString().split('T')[0];

    // Block if already assigned today (not cancelled)
    const existing = await Job.findOne({
      customerId,
      assignedDate: today,
      status: { $nin: ['Cancelled'] },
    });
    if (existing)
      return res.status(400).send("Customer already assigned today");

    const job = await Job.create({
      customerId, employeeId, serviceType,
      assignedDate: today, status: 'Pending',
    });

    const populated = await Job.findById(job._id).populate('customerId');
    res.json(populated);
  } catch (err) {
    res.status(500).send("Server error");
  }
});

// PUT /admin/reassign
// Body: { jobId, newEmployeeId }
router.put('/reassign', adminAuth, async (req, res) => {
  try {
    const { jobId, newEmployeeId } = req.body;
    if (!jobId || !newEmployeeId)
      return res.status(400).send("jobId and newEmployeeId required");

    const job = await Job.findByIdAndUpdate(
      jobId,
      { employeeId: newEmployeeId, status: 'Pending' },
      { new: true }
    ).populate('customerId');
    res.json(job);
  } catch (err) {
    res.status(500).send("Server error");
  }
});

// ═══════════════════════════════════════════════════════════════════════════════
// SEED ADMIN (one-time use)
// ═══════════════════════════════════════════════════════════════════════════════
router.post('/seed', async (req, res) => {
  try {
    const { name, email, password, secretKey } = req.body;
    if (secretKey !== 'LAUNDOOR_ADMIN_SEED')
      return res.status(403).send("Wrong secret key");

    const existing = await User.findOne({ email });
    if (existing) return res.status(400).send("Email already exists");

    const hashed = await bcrypt.hash(password, 10);
    const admin  = await User.create({ name, email, password: hashed, role: 'admin' });
    res.json(admin);
  } catch (err) {
    res.status(500).send("Server error");
  }
});

module.exports = router;