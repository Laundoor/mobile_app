const mongoose = require('mongoose');

const userSchema = new mongoose.Schema({
  name:     { type: String, required: true },
  email:    { type: String, required: true, unique: true },
  password: { type: String, required: true },
  role:     { type: String, enum: ['admin', 'employee'], default: 'employee' },
  isActive: { type: Boolean, default: false },
  lastActiveDate: { type: String, default: null },
  // Home location for distance allowance calculation
  homeLocation: {
    lat: { type: Number, default: null },
    lng: { type: Number, default: null },
  },
  homeMapsLink: { type: String, default: null }, // original Maps link
}, { timestamps: true });

module.exports = mongoose.model('User', userSchema);