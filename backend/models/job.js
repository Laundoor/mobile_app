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
  sortOrder:    { type: Number, default: 0 },     // employee sees jobs in this order

  status: {
    type: String,
    enum: ['Pending', 'In Progress', 'Completed', 'Cancelled'],
    default: 'Pending'
  },

  images: {
    before:    { type: String, default: null },
    after:     [{ label: { type: String }, url: { type: String } }],
    towelSoak: { type: String, default: null },
    // Interior-specific 8-photo sets (only for Interior Standard/Premium jobs)
    interiorBefore: [{ label: { type: String }, url: { type: String } }],
    interiorAfter:  [{ label: { type: String }, url: { type: String } }],
  },

  completedAt:       { type: Date, default: null },
  beforeUploadedAt:  { type: Date, default: null },
  cancelledAt:       { type: Date, default: null },
  cancelPhotoUrl:    { type: String, default: null },
  cancelReason:      { type: String, default: null },

  complaint: {
    raised:             { type: Boolean, default: false },
    reason:             { type: String, default: null },
    note:               { type: String, default: null },
    raisedAt:           { type: Date,   default: null },
    resolved:           { type: Boolean, default: false },
    resolvedAt:         { type: Date,   default: null },
    resolvedBy:         { type: String, default: null },
    resolvedByReassign: { type: Boolean, default: false }, // true = resolved via reassignment, not payable for original employee
  },

  // If this job was reassigned, points to the new job created for another employee
  reassignedJobId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Job',
    default: null,
  },
  // If this job is a reassignment, points to the original complained job
  originalJobId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Job',
    default: null,
  },

}, { timestamps: true });

module.exports = mongoose.model('Job', jobSchema);