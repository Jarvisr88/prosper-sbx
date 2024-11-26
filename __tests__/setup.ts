import "@testing-library/jest-dom";
import { prisma } from "@/lib/prisma";

declare global {
  // eslint-disable-next-line no-var
  var beforeAll: jest.Lifecycle;
  // eslint-disable-next-line no-var
  var afterAll: jest.Lifecycle;
}

beforeAll(async () => {
  await prisma.$connect();
});

afterAll(async () => {
  await prisma.$disconnect();
});
