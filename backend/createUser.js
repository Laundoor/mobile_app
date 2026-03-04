const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');
require('dotenv').config()

mongoose.connect(process.env.MONGO_URI)
  .then(() => console.log("MongoDB Connected"))
  .catch(err => console.error("MongoDB Error:", err));

async function createUser() {
  const hash = await bcrypt.hash("12345", 10);

  await mongoose.connection.collection("users").insertOne({
    name: "Admin",
    email: "admin@laundoor.in",
    password: hash,
    role: "admin",
    isActive: false,
  lastActiveDate: null    
  });

  console.log("User created");
  process.exit();
}

createUser();