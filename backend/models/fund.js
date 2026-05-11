const mongoose = require('mongoose');

// Tracks running balance for material fund and BD fund
const fundSchema = new mongoose.Schema({
  fundType:       { type: String, enum: ['material', 'bd'], required: true, unique: true },
  openingBalance: { type: Number, default: 0 }, // manually set once
  balance:        { type: Number, default: 0 },  // current running balance
}, { timestamps: true });

module.exports = mongoose.model('Fund', fundSchema);