const express = require('express');
const router  = express.Router();
const User    = require('../models/user');
const Car     = require('../models/car');
const bcrypt  = require('bcryptjs');

// ── MIDDLEWARE: simple admin check ────────────────────────────────────────────
const jwt = require('jsonwebtoken');

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
// EMPLOYEE MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

// POST /admin/employees — create employee
router.post('/employees', adminAuth, async (req, res) => {
  const { name, email, password } = req.body;
  if (!name || !email || !password)
    return res.status(400).send("name, email, password required");

  const existing = await User.findOne({ email });
  if (existing) return res.status(400).send("Email already exists");

  const hashed = await bcrypt.hash(password, 10);
  const user = await User.create({
    name, email, password: hashed, role: 'employee'
  });
  res.json(user);
});

// GET /admin/employees — list all employees with their car counts
router.get('/employees', adminAuth, async (req, res) => {
  const today = new Date().toISOString().split('T')[0];
  const employees = await User.find({ role: 'employee' })
    .select('-password');

  // Reset isActive for employees whose lastActiveDate is not today
  const result = employees.map(emp => {
    const obj = emp.toObject();
    if (obj.lastActiveDate !== today) obj.isActive = false;
    return obj;
  });

  // Attach car counts per employee
  const withCars = await Promise.all(result.map(async (emp) => {
    const cars = await Car.find({ employeeId: emp._id.toString() });
    const today = new Date().toISOString().split('T')[0];
    const todayCars = cars.filter(c => c.assignedDate === today);
    return {
      ...emp,
      totalCars:     cars.length,
      todayCars:     todayCars.length,
      pendingCars:   todayCars.filter(c => c.status === 'Pending').length,
      inProgressCars:todayCars.filter(c => c.status === 'In Progress').length,
      completedCars: todayCars.filter(c => c.status === 'Completed').length,
    };
  }));

  res.json(withCars);
});

// GET /admin/employees/:id — single employee with all their cars + photos
router.get('/employees/:id', adminAuth, async (req, res) => {
  const emp = await User.findById(req.params.id).select('-password');
  if (!emp) return res.status(404).send("Employee not found");

  const cars = await Car.find({ employeeId: req.params.id });
  res.json({ employee: emp, cars });
});

// DELETE /admin/employees/:id
router.delete('/employees/:id', adminAuth, async (req, res) => {
  await User.findByIdAndDelete(req.params.id);
  res.send("Deleted");
});

// ═══════════════════════════════════════════════════════════════════════════════
// CUSTOMER MANAGEMENT
// ═══════════════════════════════════════════════════════════════════════════════

// POST /admin/customers — create customer (unassigned)
router.post('/customers', adminAuth, async (req, res) => {
  const { customerName, address, vehicleNumber, vehicleColor, carModel } = req.body;
  if (!customerName) return res.status(400).send("customerName required");

  const car = await Car.create({
    employeeId:   '',   // unassigned
    customerName,
    address,
    vehicleNumber,
    vehicleColor,
    carModel,
    assignedDate: null,
  });
  res.json(car);
});

// GET /admin/customers — list all customers
router.get('/customers', adminAuth, async (req, res) => {
  const cars = await Car.find().sort({ createdAt: -1 });
  res.json(cars);
});

// GET /admin/customers/:id — single customer with all photos
router.get('/customers/:id', adminAuth, async (req, res) => {
  const car = await Car.findById(req.params.id);
  if (!car) return res.status(404).send("Customer not found");
  res.json(car);
});

// PUT /admin/customers/:id — update customer details
router.put('/customers/:id', adminAuth, async (req, res) => {
  const car = await Car.findByIdAndUpdate(req.params.id, req.body, { new: true });
  res.json(car);
});

// DELETE /admin/customers/:id
router.delete('/customers/:id', adminAuth, async (req, res) => {
  await Car.findByIdAndDelete(req.params.id);
  res.send("Deleted");
});

// ═══════════════════════════════════════════════════════════════════════════════
// ASSIGNMENT
// ═══════════════════════════════════════════════════════════════════════════════

// POST /admin/assign — assign customer to employee
// Body: { carId, employeeId }
router.post('/assign', adminAuth, async (req, res) => {
  const { carId, employeeId } = req.body;
  if (!carId || !employeeId)
    return res.status(400).send("carId and employeeId required");

  const today = new Date().toISOString().split('T')[0];

  // Check: is this customer already assigned to someone today?
  const car = await Car.findById(carId);
  if (!car) return res.status(404).send("Car not found");

  if (car.assignedDate === today && car.employeeId) {
    return res.status(400).send(
      "Customer already assigned today. Use reassign to change employee."
    );
  }

  // Check: employee doesn't already have this exact car today
  const duplicate = await Car.findOne({
    _id:          carId,
    employeeId:   employeeId,
    assignedDate: today,
  });
  if (duplicate)
    return res.status(400).send("Already assigned to this employee today");

  const updated = await Car.findByIdAndUpdate(
    carId,
    { employeeId, assignedDate: today, status: 'Pending' },
    { new: true }
  );
  res.json(updated);
});

// PUT /admin/reassign — reassign customer to different employee
// Body: { carId, newEmployeeId }
router.put('/reassign', adminAuth, async (req, res) => {
  const { carId, newEmployeeId } = req.body;
  if (!carId || !newEmployeeId)
    return res.status(400).send("carId and newEmployeeId required");

  const today = new Date().toISOString().split('T')[0];
  const updated = await Car.findByIdAndUpdate(
    carId,
    { employeeId: newEmployeeId, assignedDate: today, status: 'Pending' },
    { new: true }
  );
  res.json(updated);
});

// ═══════════════════════════════════════════════════════════════════════════════
// DASHBOARD
// ═══════════════════════════════════════════════════════════════════════════════

// GET /admin/dashboard — summary for all employees today
router.get('/dashboard', adminAuth, async (req, res) => {
  const today = new Date().toISOString().split('T')[0];

  const employees = await User.find({ role: 'employee' }).select('-password');
  const allCars   = await Car.find({ assignedDate: today });

  const data = employees.map(emp => {
    const empCars = allCars.filter(
      c => c.employeeId === emp._id.toString()
    );
    const isActiveToday = emp.lastActiveDate === today && emp.isActive;
    return {
      _id:           emp._id,
      name:          emp.name,
      email:         emp.email,
      isActive:      isActiveToday,
      totalToday:    empCars.length,
      pending:       empCars.filter(c => c.status === 'Pending').length,
      inProgress:    empCars.filter(c => c.status === 'In Progress').length,
      completed:     empCars.filter(c => c.status === 'Completed').length,
      cancelled:     empCars.filter(c => c.status === 'Cancelled').length,
    };
  });

  res.json(data);
});

// ═══════════════════════════════════════════════════════════════════════════════
// CREATE FIRST ADMIN (run once, no auth needed)
// ═══════════════════════════════════════════════════════════════════════════════
// POST /admin/seed — creates admin user (disable after first use)
router.post('/seed', async (req, res) => {
  const { name, email, password, secretKey } = req.body;
  if (secretKey !== 'LAUNDOOR_ADMIN_SEED')
    return res.status(403).send("Wrong secret key");

  const existing = await User.findOne({ email });
  if (existing) return res.status(400).send("Email already exists");

  const hashed = await bcrypt.hash(password, 10);
  const admin  = await User.create({ name, email, password: hashed, role: 'admin' });
  res.json(admin);
});

module.exports = router;