const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

mongoose.connect("mongodb://127.0.0.1:27017/carwash");

async function createUser() {
  const hash = await bcrypt.hash("123456", 10);

  await mongoose.connection.collection("users").insertOne({
    name: "Easwar",
    email: "test@test.com",
    password: hash
  });

  console.log("User created");
  process.exit();
}

createUser();