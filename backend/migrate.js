// migrate.js — run ONCE with: node migrate.js
// Converts existing 'cars' collection → 'customers' + 'jobs'
// Safe to run multiple times (checks for duplicates)

const mongoose = require('mongoose');
require('dotenv').config();

// Use same DB connection as your server
mongoose.connect(process.env.MONGO_URI)
  .then(() => console.log("MongoDB Connected"))
  .catch(err => console.error("MongoDB Error:", err));

// ── Inline schemas for migration only ────────────────────────────────────────

const OldCar = mongoose.model('Car', new mongoose.Schema({
  employeeId:    String,
  customerName:  String,
  address:       String,
  vehicleNumber: String,
  vehicleColor:  String,
  carModel:      String,
  status:        String,
  images:        mongoose.Schema.Types.Mixed,
  assignedDate:  String,
}, { collection: 'cars' }));

const Customer = mongoose.model('Customer', new mongoose.Schema({
  customerName:  String,
  address:       String,
  vehicleNumber: String,
  vehicleColor:  String,
  carModel:      String,
  carType:       String,
  phone:         String,
  serviceCount:  { type: Number, default: 0 },
}, { timestamps: true, collection: 'customers' }));

const Job = mongoose.model('Job', new mongoose.Schema({
  customerId:   mongoose.Schema.Types.ObjectId,
  employeeId:   mongoose.Schema.Types.ObjectId,
  serviceType:  String,
  serviceCount: Number,
  assignedDate: String,
  status:       String,
  images:       mongoose.Schema.Types.Mixed,
  completedAt:  Date,
}, { timestamps: true, collection: 'jobs' }));

// ── Run migration ─────────────────────────────────────────────────────────────

async function migrate() {
  const cars = await OldCar.find();
  console.log(`Found ${cars.length} car records to migrate`);

  let customerCount = 0;
  let jobCount = 0;
  let skipped = 0;

  for (const car of cars) {
    try {
      // 1. Create or find matching customer by vehicle number
      let customer = await Customer.findOne({
        vehicleNumber: car.vehicleNumber
      });

      if (!customer) {
        customer = await Customer.create({
          customerName:  car.customerName  || 'Unknown',
          address:       car.address       || '',
          vehicleNumber: car.vehicleNumber || '',
          vehicleColor:  car.vehicleColor  || '',
          carModel:      car.carModel      || '',
          carType:       'Hatchback', // default — update manually in Atlas
          phone:         '',
          serviceCount:  car.status === 'Completed' ? 1 : 0,
        });
        customerCount++;
        console.log(`  ✅ Customer created: ${customer.customerName}`);
      } else {
        // Bump serviceCount if this was a completed job
        if (car.status === 'Completed') {
          await Customer.findByIdAndUpdate(customer._id, {
            $inc: { serviceCount: 1 }
          });
        }
        console.log(`  ↩️  Customer exists: ${customer.customerName}`);
      }

      // 2. Create Job record — skip if already migrated
      const existingJob = await Job.findOne({
        customerId:   customer._id,
        assignedDate: car.assignedDate || car.createdAt?.toISOString().split('T')[0],
        employeeId:   car.employeeId,
      });

      if (existingJob) {
        console.log(`  ⏭️  Job already exists for ${customer.customerName}, skipping`);
        skipped++;
        continue;
      }

      // Normalise images from old format to new format
      let images = {
        selfie: null,
        towels: [],
        before: null,
        after:  [],
      };

      if (car.images) {
        // Handle both old array format and new format
        if (car.images.selfie) images.selfie = car.images.selfie;
        if (car.images.towels) images.towels = car.images.towels;
        if (car.images.before) {
          // Old format: before was an array
          images.before = Array.isArray(car.images.before)
            ? (car.images.before[0] || null)
            : car.images.before;
        }
        if (car.images.after) {
          // Old format: after was array of strings
          if (Array.isArray(car.images.after)) {
            images.after = car.images.after.map((url, i) => ({
              label: `Photo ${i + 1}`,
              url,
            }));
          } else {
            images.after = car.images.after;
          }
        }
        if (car.images.attendance && car.images.attendance.length > 0) {
          // Old format had attendance array — map to selfie + towels
          if (!images.selfie) images.selfie = car.images.attendance[0];
          if (images.towels.length === 0) images.towels = car.images.attendance.slice(1);
        }
      }

      const employeeObjectId = car.employeeId
        ? new mongoose.Types.ObjectId(car.employeeId)
        : null;

      await Job.create({
        customerId:   customer._id,
        employeeId:   employeeObjectId,
        serviceType:  'Exterior',  // default — update manually in Atlas
        serviceCount: car.status === 'Completed' ? customer.serviceCount : 0,
        assignedDate: car.assignedDate
          || car.createdAt?.toISOString().split('T')[0]
          || new Date().toISOString().split('T')[0],
        status:      car.status || 'Pending',
        images,
        completedAt: car.status === 'Completed' ? new Date() : null,
      });

      jobCount++;
      console.log(`  ✅ Job created for ${customer.customerName} (${car.status})`);

    } catch (err) {
      console.error(`  ❌ Error migrating car ${car._id}:`, err.message);
    }
  }

  console.log('\n══════════════════════════════════');
  console.log(`Migration complete:`);
  console.log(`  Customers created : ${customerCount}`);
  console.log(`  Jobs created      : ${jobCount}`);
  console.log(`  Skipped           : ${skipped}`);
  console.log('══════════════════════════════════');
  console.log('\nNext steps:');
  console.log('  1. Check customers and jobs in Atlas');
  console.log('  2. Update carType and serviceType fields manually where needed');
  console.log('  3. Rename cars collection to cars_backup in Atlas');
  console.log('  4. Update server.js to use new routes');
  process.exit(0);
}

migrate();