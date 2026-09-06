const mongoose = require('mongoose');

// Warehouse — separate collection, designed for future inventory management
const warehouseSchema = new mongoose.Schema({
  name:     { type: String, required: true },
  address:  { type: String },
  location: {
    lat: { type: Number },
    lng: { type: Number },
  },
  mapsLink: { type: String },
  isActive: { type: Boolean, default: true },
}, { timestamps: true });

module.exports = mongoose.model('Warehouse', warehouseSchema);