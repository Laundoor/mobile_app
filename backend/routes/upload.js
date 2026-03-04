const express = require('express');
const router  = express.Router();
const multer  = require('multer');
const s3      = require('../config/s3');
const Car     = require('../models/car');
const User    = require('../models/user');
const { v4: uuidv4 } = require('uuid');

const storage = multer.memoryStorage();
const upload  = multer({ storage });

// POST /upload?carId=xxx&photoType=selfie|towel|before|after&label=FrontAngle&employeeId=xxx
router.post('/', upload.single('image'), async (req, res) => {
  const file = req.file;
  if (!file) return res.status(400).send("No file provided");

  const { carId, photoType, label, employeeId } = req.query;

  // 1. Upload to S3
  const params = {
    Bucket:      process.env.S3_BUCKET,
    Key:         `uploads/${uuidv4()}-${file.originalname}`,
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

  // 2. Save URL to Car document if carId provided
  if (carId && photoType) {
    try {
      const car = await Car.findById(carId);
      if (!car) return res.status(404).send("Car not found");

      if (photoType === 'selfie') {
        car.images.selfie = s3Url;

      } else if (photoType === 'towel') {
        if (car.images.towels.length < 6) {
          car.images.towels.push(s3Url);
        }

      } else if (photoType === 'before') {
        car.images.before = s3Url;

        // Mark employee as active for today
        if (employeeId) {
          const today = new Date().toISOString().split('T')[0];
          await User.findByIdAndUpdate(employeeId, {
            isActive:       true,
            lastActiveDate: today,
          });
        }

      } else if (photoType === 'after') {
        const afterLabel = label || `Photo ${car.images.after.length + 1}`;
        car.images.after.push({ label: afterLabel, url: s3Url });
      }

      await car.save();
    } catch (err) {
      console.error("DB save error:", err);
      // Still return the URL even if DB save fails — client can retry
    }
  }

  res.json({ url: s3Url });
});

module.exports = router;