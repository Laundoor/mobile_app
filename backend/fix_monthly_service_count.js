/**
 * fix_monthly_service_count.js
 *
 * One-time migration to:
 * 1. For each customer, count how many jobs they had completed this month (April 2026)
 * 2. Set customer.serviceCount = that monthly count
 * 3. Set customer.lastServiceMonth = "2026-04"
 * 4. Update each completed job's serviceCount snapshot to the correct monthly order
 *
 * Run on server:
 *   cd ~/mobile_app/backend
 *   node fix_monthly_service_count.js
 */

require('dotenv').config();
const mongoose = require('mongoose');

// ── Models (inline to avoid import issues) ───────────────────────────────────
const customerSchema = new mongoose.Schema({
  serviceCount:     { type: Number, default: 0 },
  lastServiceMonth: { type: String, default: null },
}, { strict: false });
const Customer = mongoose.model('Customer', customerSchema);

const jobSchema = new mongoose.Schema({
  customerId:   { type: mongoose.Schema.Types.ObjectId, ref: 'Customer' },
  status:       String,
  completedAt:  Date,
  serviceCount: { type: Number, default: 0 },
}, { strict: false });
const Job = mongoose.model('Job', jobSchema);

// ── Config ───────────────────────────────────────────────────────────────────
const CURRENT_MONTH = '2026-04';
const FROM = new Date('2026-04-01T00:00:00+05:30'); // IST midnight
const TO   = new Date('2026-05-01T00:00:00+05:30');

async function run() {
  await mongoose.connect(process.env.MONGO_URI);
  console.log('Connected to MongoDB');

  // Find all jobs completed this month
  const jobs = await Job.find({
    status:      'Completed',
    completedAt: { $gte: FROM, $lt: TO },
  }).sort({ completedAt: 1 }); // ascending — so first completed = #1

  console.log(`Found ${jobs.length} completed jobs in April 2026`);

  // Group by customerId, preserving order of completion
  const byCustomer = {};
  for (const job of jobs) {
    const cid = job.customerId.toString();
    if (!byCustomer[cid]) byCustomer[cid] = [];
    byCustomer[cid].push(job);
  }

  let jobsFixed     = 0;
  let customersFixed = 0;

  for (const [customerId, customerJobs] of Object.entries(byCustomer)) {
    // Assign monthly count in completion order
    for (let i = 0; i < customerJobs.length; i++) {
      const monthlyCount = i + 1; // #1, #2, #3...
      await Job.findByIdAndUpdate(customerJobs[i]._id,
        { $set: { serviceCount: monthlyCount } });
      jobsFixed++;
    }

    // Set customer monthly count = total completed this month
    const monthlyTotal = customerJobs.length;
    await Customer.findByIdAndUpdate(customerId, {
      $set: {
        serviceCount:     monthlyTotal,
        lastServiceMonth: CURRENT_MONTH,
      },
    });
    customersFixed++;

    console.log(`  Customer ${customerId}: ${monthlyTotal} job(s) fixed`);
  }

  // Also set lastServiceMonth on customers with no April jobs but have March history
  // so their serviceCount resets correctly on next completion
  const allCustomers = await Customer.find({
    lastServiceMonth: { $ne: CURRENT_MONTH },
  });
  console.log(`\n${allCustomers.length} customers with no April jobs — setting lastServiceMonth to null to force reset on next completion`);
  await Customer.updateMany(
    { lastServiceMonth: { $ne: CURRENT_MONTH } },
    { $set: { serviceCount: 0, lastServiceMonth: null } }
  );

  console.log(`\n✅ Done.`);
  console.log(`   Jobs fixed:      ${jobsFixed}`);
  console.log(`   Customers fixed: ${customersFixed}`);
  await mongoose.disconnect();
}

run().catch(err => {
  console.error('Migration failed:', err);
  process.exit(1);
});