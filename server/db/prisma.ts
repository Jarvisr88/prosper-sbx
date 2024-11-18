import { PrismaClient } from '@prisma/client'

const globalForPrisma = global as { prisma?: PrismaClient }

if (!globalForPrisma.prisma) {
  globalForPrisma.prisma = new PrismaClient()
}

const prisma = globalForPrisma.prisma

export default prisma