const express = require('express');
const router  = express.Router();
const User    = require('../models/user');
const bcrypt  = require('bcryptjs');
const jwt     = require('jsonwebtoken');

// POST /auth/login
router.post('/login', async (req, res) => {
  const { email, password } = req.body;

  const user = await User.findOne({ email });
  if (!user) return res.status(400).send("User not found");

  const valid = await bcrypt.compare(password, user.password);
  if (!valid) return res.status(400).send("Invalid password");

  const token = jwt.sign({ id: user._id, role: user.role }, "secretkey");

  // Reset isActive if last active date is not today
  const today = new Date().toISOString().split('T')[0];
  if (user.lastActiveDate !== today && user.isActive) {
    await User.findByIdAndUpdate(user._id, { isActive: false });
    user.isActive = false;
  }

  res.json({ token, user });
});

module.exports = router;