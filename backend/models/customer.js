const mongoose = require('mongoose');

const customerSchema = new mongoose.Schema({
  customerName:  { type: String, required: true },
  address:       { type: String, default: '' },
  vehicleNumber: { type: String, default: '' },
  vehicleColor:  { type: String, default: '' },
  carModel:      { type: String, default: '' },
  carType: {
    type: String,
    enum: ['Hatchback', 'Sedan', 'SUV'],
    default: 'Hatchback'
  },
  serviceCount:  { type: Number, default: 0 },
  phone:         { type: String, default: '' },
  // Location for distance allowance calculation
  mapsLink:  { type: String, default: null }, // Google Maps link pasted by admin
  location: {
    lat: { type: Number, default: null },
    lng: { type: Number, default: null },
  },
}, { timestamps: true });

module.exports = mongoose.model('Customer', customerSchema);