const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 5000;

app.use(cors());
app.use(express.json());

mongoose.connect("mongodb://127.0.0.1:27017/carwash");

app.use('/auth', require('./routes/auth'));
app.use('/cars', require('./routes/cars'));
app.use('/upload', require('./routes/upload'));

 app.listen(PORT, '0.0.0.0', () => {
    console.log(`🚀 Server running on port ${PORT}`);
});