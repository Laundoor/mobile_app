const mongoose = require('mongoose');

const carSchema = new mongoose.Schema({
  employeeId:    { type: String, required: true },
  customerName:  { type: String, required: true },
  address:       { type: String },
  vehicleNumber: { type: String },
  vehicleColor:  { type: String },
  carModel:      { type: String },
  status: {
    type:    String,
    enum:    ['Pending', 'In Progress', 'Completed', 'Cancelled'],
    default: 'Pending'
  },
  images: {
    selfie:      { type: String, default: null },   // single S3 URL
    towels:      [{ type: String }],                // up to 6 S3 URLs
    before:      { type: String, default: null },   // single S3 URL
    after: [{                                       // up to 8 labelled S3 URLs
      label: { type: String },
      url:   { type: String }
    }]
  },
  assignedDate: { type: String, default: null },    // "YYYY-MM-DD"
}, { timestamps: true });

module.exports = mongoose.model('Car', carSchema);