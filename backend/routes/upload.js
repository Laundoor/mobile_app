const express = require('express');
const router  = express.Router();
const multer  = require('multer');
const s3      = require('../config/s3');
const Job     = require('../models/job');
const User    = require('../models/user');

const storage = multer.memoryStorage();
const upload  = multer({ storage });

// POST /upload?jobId=xxx&photoType=selfie|towel|before|after&label=FrontAngle&employeeId=xxx
router.post('/', upload.single('image'), async (req, res) => {
  const file = req.file;
  if (!file) return res.status(400).send("No file provided");

  const { jobId, photoType, label, employeeId } = req.query;
  if (!jobId || !photoType) return res.status(400).send("jobId and photoType required");

  // Build structured S3 key: jobs/{jobId}/{photoType}-{suffix}.jpg
  let s3Key;
  if (photoType === 'selfie') {
    s3Key = `jobs/${jobId}/selfie.jpg`;
  } else if (photoType === 'towel') {
    // Get current towel count to name correctly
    const job = await Job.findById(jobId);
    const towelIndex = job ? job.images.towels.length + 1 : 1;
    s3Key = `jobs/${jobId}/towel-${towelIndex}.jpg`;
  } else if (photoType === 'before') {
    s3Key = `jobs/${jobId}/before.jpg`;
  } else if (photoType === 'after') {
    const safeLabel = (label || 'photo').toLowerCase().replace(/\s+/g, '-');
    s3Key = `jobs/${jobId}/after-${safeLabel}.jpg`;
  } else {
    s3Key = `jobs/${jobId}/${photoType}.jpg`;
  }

  // Upload to S3
  const params = {
    Bucket:      process.env.S3_BUCKET,
    Key:         s3Key,
    Body:        file.buffer,
    ContentType: file.mimetype,
    ACL:         'public-read',
  };

  let s3Url;
  try {
    const data = await s3.upload(params).promise();
    s3Url = data.Location;
  } catch (err) {
    console.error("S3 upload error:", err);
    return res.status(500).send("Upload failed");
  }

  // Save URL into the Job document
  try {
    const job = await Job.findById(jobId);
    if (!job) return res.status(404).send("Job not found");

    if (photoType === 'selfie') {
      job.images.selfie = s3Url;

    } else if (photoType === 'towel') {
      if (job.images.towels.length < 6) {
        job.images.towels.push(s3Url);
      }

    } else if (photoType === 'before') {
      job.images.before = s3Url;
      job.beforeUploadedAt = new Date(); // exact timestamp for share message
      // Mark employee active for today
      if (employeeId) {
        const today = new Date().toISOString().split('T')[0];
        await User.findByIdAndUpdate(employeeId, {
          isActive:       true,
          lastActiveDate: today,
        });
      }

    } else if (photoType === 'after') {
      const afterLabel = label || `Photo ${job.images.after.length + 1}`;
      job.images.after.push({ label: afterLabel, url: s3Url });
    }

    await job.save();
  } catch (err) {
    console.error("DB save error:", err);
    // Still return URL — client can handle retry
  }

  res.json({ url: s3Url });
});

module.exports = router;