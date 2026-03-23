const mongoose = require('mongoose');

const attendanceSchema = new mongoose.Schema({
  employeeId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  date:       { type: String, required: true }, // "YYYY-MM-DD"
  selfieUrl:        { type: String, default: null },
  selfieUploadedAt: { type: Date,   default: null }, // explicit login time
  towelUrls:  { type: [String], default: [] },

  // Soak photos (moved from Job)
  towelSoakUrl:  { type: String, default: null },
  dusterSoakUrl: { type: String, default: null }, // Saturdays only

  // Admin approvals
  selfieApproval:     { type: String, enum: ['pending','approved','rejected'], default: 'pending' },
  towelsApproval:     { type: String, enum: ['pending','approved','rejected'], default: 'pending' },
  towelSoakApproval:  { type: String, enum: ['pending','approved','rejected'], default: 'pending' },
  dusterSoakApproval: { type: String, enum: ['pending','approved','rejected'], default: 'pending' },

  // Incentive
  incentiveExcused: { type: Boolean, default: false }, // admin excuse pass
}, { timestamps: true });

// One record per employee per day
attendanceSchema.index({ employeeId: 1, date: 1 }, { unique: true });

module.exports = mongoose.model('Attendance', attendanceSchema);