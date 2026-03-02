const mongoose = require('mongoose');

const carSchema = new mongoose.Schema({
  employeeId: String,
  customerName: String,
  address: String,
  vehicleNumber: String,
  vehicleColor: String,
  carModel: String,
  status: {
    type: String,
    default: "Pending"
  },
  images: {
    before: [String],
    after: [String],
    attendance: [String],
    towels: [String]
  }
});

module.exports = mongoose.model('Car', carSchema);