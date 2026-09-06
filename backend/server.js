const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 5000;

app.use(cors());
app.use(express.json());

// Register models explicitly so they're available across all routes
require('./models/invoice');
require('./models/salary_slip');
require('./models/expense');
require('./models/fund');

mongoose.connect(process.env.MONGO_URI)
  .then(() => console.log("MongoDB Connected"))
  .catch(err => console.error("MongoDB Error:", err));

// Bump minBuild whenever you release a mandatory update
app.get('/app/version', (req, res) => {
  res.json({ minBuild: 2 });
});

require('./models/warehouse'); // register warehouse model

app.use('/auth',       require('./routes/auth'));
app.use('/jobs',       require('./routes/jobs'));        // NEW
app.use('/customers',  require('./routes/customers'));   // NEW
app.use('/upload',     require('./routes/upload'));
app.use('/admin',      require('./routes/admin'));       // ← NEW
app.use('/supervisor', require('./routes/supervisor')); // supervisor endpoints

// Keep old /cars route alive temporarily during transition
// Remove after confirming employee app is fully updated
app.use('/cars', require('./routes/cars'));

 app.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 Server running on port ${PORT}`);
});