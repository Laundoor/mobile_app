const mongoose = require('mongoose');

const attendanceSchema = new mongoose.Schema({
  employeeId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  date:       { type: String, required: true }, // "YYYY-MM-DD"
  selfieUrl:  { type: String, default: null },
  towelUrls:  { type: [String], default: [] },

  // Admin approval per photo type
  selfieApproval:    { type: String, enum: ['pending', 'approved', 'rejected'], default: 'pending' },
  towelsApproval:    { type: String, enum: ['pending', 'approved', 'rejected'], default: 'pending' },
  towelSoakApproval: { type: String, enum: ['pending', 'approved', 'rejected'], default: 'pending' },
}, { timestamps: true });

// One record per employee per day
attendanceSchema.index({ employeeId: 1, date: 1 }, { unique: true });

module.exports = mongoose.model('Attendance', attendanceSchema);