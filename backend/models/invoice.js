const mongoose = require('mongoose');

const invoiceSchema = new mongoose.Schema({
  // Global sequential invoice number — e.g. "LD-2026-04-047"
  invoiceNumber: { type: String, required: true, unique: true },

  // Billing period
  month: { type: Number, required: true }, // 1-12
  year:  { type: Number, required: true },

  // Customer reference + snapshot at invoice time
  customerId:    { type: mongoose.Schema.Types.ObjectId, ref: 'Customer', required: true },
  customerName:  { type: String, default: '' },
  vehicleNumber: { type: String, default: '' },
  carModel:      { type: String, default: '' },
  carType:       { type: String, default: '' },
  customerPhone: { type: String, default: '' },

  // Payment contact snapshot
  paymentContact: {
    name:      { type: String, default: '' },
    number:    { type: String, default: '' },
    qrImageUrl:{ type: String, default: null },
  },

  // Job stats for the month
  attempted: { type: Number, default: 0 },
  cleaned:   { type: Number, default: 0 },
  cancelled: { type: Number, default: 0 },

  // Line items — e.g. [{ label: 'Hatchback', amount: 1960 }, { label: 'Interior Standard', amount: 100 }]
  lineItems: [{
    label:  { type: String },
    amount: { type: Number },
  }],

  grandTotal: { type: Number, default: 0 },

  // Share status
  shared:   { type: Boolean, default: false },
  sharedAt: { type: Date, default: null },

}, { timestamps: true });

// Counter model for global invoice sequence
const invoiceCounterSchema = new mongoose.Schema({
  _id:     { type: String, required: true }, // key: 'invoiceNumber'
  seq:     { type: Number, default: 0 },
});
const InvoiceCounter = mongoose.model('InvoiceCounter', invoiceCounterSchema);

// Helper to get next invoice number
async function getNextInvoiceNumber(month, year) {
  const counter = await InvoiceCounter.findByIdAndUpdate(
    'invoiceNumber',
    { $inc: { seq: 1 } },
    { new: true, upsert: true }
  );
  const mm  = String(month).padStart(2, '0');
  const seq = String(counter.seq).padStart(3, '0');
  return `LD-${year}-${mm}-${seq}`;
}

const Invoice = mongoose.model('Invoice', invoiceSchema);

module.exports = { Invoice, getNextInvoiceNumber };