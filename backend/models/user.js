const mongoose = require('mongoose');

const userSchema = new mongoose.Schema({
  name:     { type: String, required: true },
  email:    { type: String, required: true, unique: true },
  password: { type: String, required: true },
  role:     { type: String, enum: ['admin', 'employee'], default: 'employee' },
  isActive: { type: Boolean, default: false },
  lastActiveDate: { type: String, default: null },
  phone:       { type: String, default: null },
  joiningDate: { type: String, default: null }, // "YYYY-MM-DD"
  // Home location for distance allowance
  homeLocation: {
    lat: { type: Number, default: null },
    lng: { type: Number, default: null },
  },
  homeMapsLink: { type: String, default: null },
  // Document & profile photos (S3 URLs)
  photos: {
    profile:       { type: String, default: null },
    aadhaar_front: { type: String, default: null },
    aadhaar_back:  { type: String, default: null },
    pan_front:     { type: String, default: null },
    pan_back:      { type: String, default: null },
  },
}, { timestamps: true });

module.exports = mongoose.model('User', userSchema);