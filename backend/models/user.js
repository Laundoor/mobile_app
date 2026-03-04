const mongoose = require('mongoose');

const userSchema = new mongoose.Schema({
  name:     { type: String, required: true },
  email:    { type: String, required: true, unique: true },
  password: { type: String, required: true },
  role:     { type: String, enum: ['admin', 'employee'], default: 'employee' },
  isActive: { type: Boolean, default: false }, // true after first before-photo uploaded today
  lastActiveDate: { type: String, default: null }, // "YYYY-MM-DD"
}, { timestamps: true });

module.exports = mongoose.model('User', userSchema);