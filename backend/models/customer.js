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
  interiorType: {
    type: String,
    enum: ['None', 'Interior Standard', 'Interior Premium'],
    default: 'None'
  },
  serviceCount:      { type: Number, default: 0 }, // monthly count — resets each month
  lastServiceMonth:  { type: String, default: null }, // "YYYY-MM" of last completion
  // Payment contact — which business number this customer pays to
  paymentContact: {
    name:       { type: String, default: null },
    number:     { type: String, default: null },
    qrImageUrl: { type: String, default: null },
  },
  phone:         { type: String, default: '' },
  carPhoto:      { type: String, default: null }, // S3 URL of car photo
  // Location for distance allowance calculation
  mapsLink:  { type: String, default: null }, // Google Maps link pasted by admin
  location: {
    lat: { type: Number, default: null },
    lng: { type: Number, default: null },
  },
}, { timestamps: true });

module.exports = mongoose.model('Customer', customerSchema);