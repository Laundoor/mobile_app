const express = require('express');
const router = express.Router();
const Car = require('../models/car');

router.get('/:employeeId', async (req, res) => {
  const cars = await Car.find({ employeeId: req.params.employeeId });
  res.json(cars);
});

router.put('/status/:id', async (req, res) => {
  await Car.findByIdAndUpdate(req.params.id, {
    status: req.body.status
  });
  res.send("Updated");
});

module.exports = router;