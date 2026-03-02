const express = require('express');
const router = express.Router();
const multer = require('multer');
const s3 = require('../config/s3');
const { v4: uuidv4 } = require('uuid');

const storage = multer.memoryStorage();
const upload = multer({ storage: storage });

router.post('/', upload.single('image'), async (req, res) => {
  const file = req.file;

  const params = {
    Bucket: process.env.S3_BUCKET,
    Key: `uploads/${uuidv4()}-${file.originalname}`,
    Body: file.buffer,
    ContentType: file.mimetype,
    ACL: 'public-read'
  };

  try {
    const data = await s3.upload(params).promise();
    res.json({ url: data.Location });
  } catch (err) {
    console.error(err);
    res.status(500).send("Upload failed");
  }
});

module.exports = router;