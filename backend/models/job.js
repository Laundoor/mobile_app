const mongoose = require('mongoose');

const jobSchema = new mongoose.Schema({
  customerId:  {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Customer',
    required: true
  },
  employeeId:  {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true
  },
  serviceType: {
    type: String,
    enum: ['Exterior', 'Interior Standard', 'Interior Premium'],
    required: true
  },
  serviceCount: { type: Number, default: 0 }, // snapshot at time of completion

  assignedDate: { type: String, default: null }, // "YYYY-MM-DD"

  status: {
    type: String,
    enum: ['Pending', 'In Progress', 'Completed', 'Cancelled'],
    default: 'Pending'
  },

  images: {
    selfie: { type: String, default: null },
    towels: [{ type: String }],              // up to 6 S3 URLs
    before: { type: String, default: null },
    after:  [{
      label: { type: String },
      url:   { type: String }
    }]
  },

  completedAt: { type: Date, default: null },

}, { timestamps: true });

module.exports = mongoose.model('Job', jobSchema);