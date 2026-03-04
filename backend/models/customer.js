const mongoose = require('mongoose');

const customerSchema = new mongoose.Schema({
  customerName:  { type: String, required: true },
  address:       { type: String, default: '' },
  vehicleNumber: { type: String, default: '' },
  vehicleColor:  { type: String, default: '' },
  carModel:      { type: String, default: '' },
  carType:       {
    type: String,
    enum: ['Hatchback', 'Sedan', 'SUV'],
    default: 'Hatchback'
  },
  serviceCount:  { type: Number, default: 0 }, // incremented on each completed job
  phone:         { type: String, default: '' },
}, { timestamps: true });

module.exports = mongoose.model('Customer', customerSchema);