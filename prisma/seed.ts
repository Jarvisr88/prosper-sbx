import { PrismaClient } from "@prisma/client";
import { hash } from "../lib/auth";

const prisma = new PrismaClient();

async function main() {
  // Clear existing data
  await prisma.users.deleteMany({});

  // Create test users
  const users = [
    {
      username: "admin",
      email: "admin@example.com",
      role: "ADMIN",
      password: "admin123",
    },
    {
      username: "user",
      email: "user@example.com",
      role: "USER",
      password: "user123",
    },
  ];

  for (const userData of users) {
    const { salt, hash: password_hash } = await hash(userData.password);
    const user = await prisma.users.create({
      data: {
        username: userData.username,
        email: userData.email,
        role: userData.role,
        salt,
        password_hash,
      },
    });
    console.log(`Created user: ${user.email}`);
  }
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
