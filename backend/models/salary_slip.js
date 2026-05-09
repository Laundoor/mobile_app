const mongoose = require('mongoose');

const bonusItemSchema = new mongoose.Schema({
  amount: { type: Number, required: true },
  reason: { type: String, default: '' },
}, { _id: false });

const salarySlipSchema = new mongoose.Schema({
  employeeId:   { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
  month:        { type: Number, required: true }, // 1-12
  year:         { type: Number, required: true },

  // Snapshot of employee details at slip time
  employeeName:  { type: String, default: '' },
  employeePhone: { type: String, default: '' },
  joiningDate:   { type: String, default: '' },

  // Computed salary components (pulled from salary endpoint)
  baseSalary:        { type: Number, default: 0 },
  distanceAllowance: { type: Number, default: 0 },
  dailyIncentive:    { type: Number, default: 0 },
  computedTotal:     { type: Number, default: 0 },
  daysWorked:        { type: Number, default: 0 },
  totalWorkingDays:  { type: Number, default: 0 }, // base + distance + incentive

  // Manual bonus fields — only saved if admin enters them
  salesIncentive:      [bonusItemSchema],
  employeeReferral:    [bonusItemSchema],
  bonus:               [bonusItemSchema],

  // Deductions — multiple line items with reasons
  deductions: [bonusItemSchema],

  // Net total = computedTotal + all bonuses - all deductions
  netTotal: { type: Number, default: 0 },

  // Payment status
  paymentStatus: { type: String, enum: ['Pending', 'Paid'], default: 'Pending' },
  paidAt:        { type: Date, default: null },

}, { timestamps: true });

module.exports = mongoose.model('SalarySlip', salarySlipSchema);