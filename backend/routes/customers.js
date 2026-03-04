const express  = require('express');
const router   = express.Router();
const Customer = require('../models/customer');
const Job      = require('../models/job');
const User     = require('../models/user');

// ── GET /customers — list all customers ──────────────────────────────────────
router.get('/', async (req, res) => {
  try {
    const customers = await Customer.find().sort({ createdAt: -1 });
    res.json(customers);
  } catch (err) {
    res.status(500).send("Server error");
  }
});

// ── GET /customers/:id — single customer ─────────────────────────────────────
router.get('/:id', async (req, res) => {
  try {
    const customer = await Customer.findById(req.params.id);
    if (!customer) return res.status(404).send("Customer not found");
    res.json(customer);
  } catch (err) {
    res.status(500).send("Server error");
  }
});

// ── GET /customers/:id/history — all jobs for this customer ──────────────────
router.get('/:id/history', async (req, res) => {
  try {
    const jobs = await Job.find({ customerId: req.params.id })
      .sort({ createdAt: -1 })
      .populate('employeeId', 'name email'); // attach employee name

    res.json(jobs);
  } catch (err) {
    res.status(500).send("Server error");
  }
});

// ── POST /customers — create customer ────────────────────────────────────────
router.post('/', async (req, res) => {
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

// ── PUT /customers/:id — update customer details ─────────────────────────────
router.put('/:id', async (req, res) => {
  try {
    const customer = await Customer.findByIdAndUpdate(
      req.params.id, req.body, { new: true }
    );
    res.json(customer);
  } catch (err) {
    res.status(500).send("Server error");
  }
});

// ── DELETE /customers/:id ─────────────────────────────────────────────────────
router.delete('/:id', async (req, res) => {
  try {
    await Customer.findByIdAndDelete(req.params.id);
    res.send("Deleted");
  } catch (err) {
    res.status(500).send("Server error");
  }
});

module.exports = router;