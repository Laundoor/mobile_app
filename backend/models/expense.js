const mongoose = require('mongoose');

const expenseSchema = new mongoose.Schema({
  month:    { type: Number, required: true }, // 1-12
  year:     { type: Number, required: true },
  date:     { type: String, required: true }, // YYYY-MM-DD

  // Which ledger this belongs to
  // 'pl'       = P&L expense (Fuel, Mobile, IT, Equipment, Welfare, Misc)
  // 'material' = Material fund spending
  // 'bd'       = BD fund spending
  // 'fund-top-up' = Admin adding money to material/bd fund (credits fund, debits revenue)
  fundType: {
    type: String,
    enum: ['pl', 'material', 'bd', 'material-topup', 'bd-topup', 'manual-salary'],
    default: 'pl',
  },

  category: {
    type: String,
    enum: [
      // P&L categories
      'Fuel', 'Mobile Recharge', 'IT & Marketing', 'Equipment',
      'Team Dinner', 'Festival Expenses', 'Misc',
      // Material fund spending
      'Supplies',
      // BD fund spending
      'BD Expense',
      // Top-ups
      'Material Fund Top-up', 'BD Fund Top-up',
      // Manual salary (support staff)
      'Manual Salary',
    ],
    required: true,
  },

  amount:     { type: Number, required: true },
  note:       { type: String, default: '' },
  receiptUrl: { type: String, default: null }, // S3 URL optional

}, { timestamps: true });

module.exports = mongoose.model('Expense', expenseSchema);