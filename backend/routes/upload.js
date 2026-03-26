const express    = require('express');
const router     = express.Router();
const multer     = require('multer');
const s3         = require('../config/s3');
const Job        = require('../models/job');
const User       = require('../models/user');
const Attendance = require('../models/attendance');

const storage = multer.memoryStorage();
const upload  = multer({ storage });

// ─── helpers ──────────────────────────────────────────────────────────────────

// Returns current date in IST (UTC+5:30) as YYYY-MM-DD
function today() {
  const now = new Date();
  const ist = new Date(now.getTime() + 5.5 * 60 * 60 * 1000);
  return ist.toISOString().split('T')[0];
}

async function s3Upload(key, file) {
  const params = {
    Bucket:      process.env.S3_BUCKET,
    Key:         key,
    Body:        file.buffer,
    ContentType: file.mimetype,
    ACL:         'public-read',
  };
  const data = await s3.upload(params).promise();
  return data.Location;
}

// ─── POST /upload ─────────────────────────────────────────────────────────────
// photoType: selfie | towel | towel_soak | duster_soak | before | after | cancel
//
// selfie / towel / towel_soak / duster_soak → require employeeId, store in Attendance
// before / after / cancel                   → require jobId
// ─────────────────────────────────────────────────────────────────────────────
router.post('/', upload.single('image'), async (req, res) => {
  const file = req.file;
  if (!file) return res.status(400).send("No file provided");

  const { photoType, label, employeeId, jobId } = req.query;
  if (!photoType) return res.status(400).send("photoType required");

  // ── SELFIE → attendance ───────────────────────────────────────────────────
  if (photoType === 'selfie') {
    if (!employeeId) return res.status(400).send("employeeId required for selfie");
    const date   = today();
    const s3Key  = `attendance/${employeeId}/${date}/selfie.jpg`;
    let url;
    try { url = await s3Upload(s3Key, file); }
    catch (err) { console.error("S3 error:", err); return res.status(500).send("Upload failed"); }
    try {
      await Attendance.findOneAndUpdate(
        { employeeId, date },
        { $set: { selfieUrl: url, selfieUploadedAt: new Date() } },
        { upsert: true, new: true }
      );
      // Mark employee active as soon as selfie is uploaded —
      // proves they showed up even if first job is later cancelled
      await User.findByIdAndUpdate(employeeId, {
        isActive: true, lastActiveDate: date,
      });
    } catch (err) { console.error("DB error:", err); }
    return res.json({ url });
  }

  // ── TOWEL → attendance ────────────────────────────────────────────────────
  if (photoType === 'towel') {
    if (!employeeId) return res.status(400).send("employeeId required for towel");
    const date = today();
    const existing = await Attendance.findOne({ employeeId, date });

    // Hard limit: max 6 towels per day
    if (existing && existing.towelUrls.length >= 6) {
      return res.status(400).send("Maximum 6 towel photos already uploaded for today");
    }

    const towelIndex = existing ? existing.towelUrls.length + 1 : 1;
    const s3Key = `attendance/${employeeId}/${date}/towel-${towelIndex}.jpg`;
    let url;
    try { url = await s3Upload(s3Key, file); }
    catch (err) { console.error("S3 error:", err); return res.status(500).send("Upload failed"); }
    try {
      await Attendance.findOneAndUpdate(
        { employeeId, date },
        { $push: { towelUrls: url } },
        { upsert: true, new: true }
      );
    } catch (err) { console.error("DB error:", err); }
    return res.json({ url });
  }

  // ── TOWEL SOAK → attendance ───────────────────────────────────────────────
  if (photoType === 'towel_soak') {
    if (!employeeId) return res.status(400).send("employeeId required for towel_soak");
    const date  = today();
    const s3Key = `attendance/${employeeId}/${date}/towel-soak.jpg`;
    let url;
    try { url = await s3Upload(s3Key, file); }
    catch (err) { console.error("S3 error:", err); return res.status(500).send("Upload failed"); }
    try {
      await Attendance.findOneAndUpdate(
        { employeeId, date },
        { $set: { towelSoakUrl: url } },
        { upsert: true, new: true }
      );
    } catch (err) { console.error("DB error:", err); }
    return res.json({ url });
  }

  // ── DUSTER SOAK → attendance (Saturdays only) ─────────────────────────────
  if (photoType === 'duster_soak') {
    if (!employeeId) return res.status(400).send("employeeId required for duster_soak");
    const date  = today();
    const s3Key = `attendance/${employeeId}/${date}/duster-soak.jpg`;
    let url;
    try { url = await s3Upload(s3Key, file); }
    catch (err) { console.error("S3 error:", err); return res.status(500).send("Upload failed"); }
    try {
      await Attendance.findOneAndUpdate(
        { employeeId, date },
        { $set: { dusterSoakUrl: url } },
        { upsert: true, new: true }
      );
    } catch (err) { console.error("DB error:", err); }
    return res.json({ url });
  }

  // ── JOB PHOTOS → require jobId ────────────────────────────────────────────
  if (!jobId) return res.status(400).send("jobId required");

  let s3Key;
  if (photoType === 'before') {
    s3Key = `jobs/${jobId}/before.jpg`;
  } else if (photoType === 'after') {
    const safeLabel = (label || 'photo').toLowerCase().replace(/\s+/g, '-');
    s3Key = `jobs/${jobId}/after-${safeLabel}.jpg`;
  } else if (photoType === 'cancel') {
    s3Key = `jobs/${jobId}/cancel.jpg`;
  } else {
    s3Key = `jobs/${jobId}/${photoType}.jpg`;
  }

  let s3Url;
  try { s3Url = await s3Upload(s3Key, file); }
  catch (err) { console.error("S3 error:", err); return res.status(500).send("Upload failed"); }

  try {
    const job = await Job.findById(jobId);
    if (!job) return res.status(404).send("Job not found");

    if (photoType === 'before') {
      job.images.before    = s3Url;
      job.beforeUploadedAt = new Date();
      if (employeeId) {
        await User.findByIdAndUpdate(employeeId, {
          isActive: true, lastActiveDate: today(),
        });
      }
    } else if (photoType === 'after') {
      const afterLabel = label || `Photo ${job.images.after.length + 1}`;
      job.images.after.push({ label: afterLabel, url: s3Url });
    } else if (photoType === 'cancel') {
      job.cancelPhotoUrl = s3Url;
    }

    await job.save();
  } catch (err) {
    console.error("DB save error:", err);
  }

  res.json({ url: s3Url });
});

// ─── POST /upload/customer-photo ─────────────────────────────────────────────
router.post('/customer-photo', upload.single('image'), async (req, res) => {
  const file = req.file;
  if (!file) return res.status(400).send("No file provided");
  const { customerId } = req.query;
  if (!customerId) return res.status(400).send("customerId required");

  const s3Key = `customers/${customerId}/car.jpg`;
  let s3Url;
  try { s3Url = await s3Upload(s3Key, file); }
  catch (err) { console.error("S3 error:", err); return res.status(500).send("Upload failed"); }

  try {
    const Customer = require('../models/customer');
    await Customer.findByIdAndUpdate(customerId, { carPhoto: s3Url });
  } catch (err) { console.error("DB error:", err); }

  res.json({ url: s3Url });
});
router.post('/employee-doc', upload.single('image'), async (req, res) => {
  const file = req.file;
  if (!file) return res.status(400).send("No file provided");

  const { empId, docType } = req.query;
  if (!empId || !docType) return res.status(400).send("empId and docType required");

  const allowed = ['profile', 'aadhaar_front', 'aadhaar_back', 'pan_front', 'pan_back'];
  if (!allowed.includes(docType)) return res.status(400).send("Invalid docType");

  const s3Key = `employees/${empId}/${docType}.jpg`;
  let s3Url;
  try { s3Url = await s3Upload(s3Key, file); }
  catch (err) { console.error("S3 error:", err); return res.status(500).send("Upload failed"); }

  try {
    await User.findByIdAndUpdate(empId, { [`photos.${docType}`]: s3Url });
  } catch (err) { console.error("DB save error:", err); }

  res.json({ url: s3Url });
});

module.exports = router;