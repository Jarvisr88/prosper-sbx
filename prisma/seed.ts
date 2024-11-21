import { PrismaClient } from '@prisma/client'
import crypto from 'crypto'

const prisma = new PrismaClient()

const roles = ['admin', 'manager', 'user', 'developer', 'analyst'] as const
const departments = ['Engineering', 'Product', 'Sales', 'Marketing', 'Support'] as const
const categories = ['PORTFOLIO', 'RELATIONSHIP', 'OPERATIONS', 'SUCCESS', 'PRODUCTIVITY', 'ENABLEMENT', 'RESPONSIBILITY'] as const

function generateHash() {
  const salt = crypto.randomBytes(16).toString('hex')
  const hash = crypto.pbkdf2Sync('password123', salt, 1000, 64, 'sha512').toString('hex')
  return { hash, salt }
}

async function seed() {
  // First clear existing data
  await prisma.users.deleteMany({})
  await prisma.access_control.deleteMany({})
  await prisma.employee_manager_hierarchy.deleteMany({})
  await prisma.department.deleteMany({})

  // Create departments and store their IDs
  const departmentMap = new Map<string, number>()
  
  for (const dept of departments) {
    const createdDept = await prisma.department.create({
      data: {
        department_name: dept,
        active: true
      }
    })
    departmentMap.set(dept, createdDept.department_id)
  }

  // Create access control roles with category permissions
  for (const role of roles) {
    await prisma.access_control.create({
      data: {
        role_name: role,
        permissions: {
          create: role === 'admin',
          read: true,
          update: ['admin', 'manager'].includes(role),
          delete: role === 'admin',
          categories: categories.reduce((acc, cat) => ({
            ...acc,
            [cat]: ['admin', 'manager'].includes(role)
          }), {})
        },
        description: `${role.charAt(0).toUpperCase() + role.slice(1)} role permissions`,
        active: true
      }
    })
  }

  // Create 100 users with department assignments
  for (let i = 0; i < 100; i++) {
    const { hash, salt } = generateHash()
    const role = roles[Math.floor(Math.random() * roles.length)]
    const selectedDept = departments[Math.floor(Math.random() * departments.length)] as string
    const departmentId = departmentMap.get(selectedDept)
    if (!departmentId) continue // Skip if department not found
    
    const firstName = `User${i + 1}`
    const lastName = `Test${i + 1}`
    const email = `${firstName.toLowerCase()}.${lastName.toLowerCase()}@prosper.com`
    
    const user = await prisma.users.create({
      data: {
        username: `${firstName.toLowerCase()}${i + 1}`,
        email,
        password_hash: hash,
        salt,
        role,
        is_active: Math.random() > 0.1, // 90% active
        last_login: new Date(Date.now() - Math.floor(Math.random() * 30) * 24 * 60 * 60 * 1000),
        created_at: new Date(Date.now() - Math.floor(Math.random() * 365) * 24 * 60 * 60 * 1000),
      }
    })

    // Create employee hierarchy entry with department
    await prisma.employee_manager_hierarchy.create({
      data: {
        employee_id: user.user_id,
        employee_name: `${firstName} ${lastName}`,
        department_id: departmentId,
        role: role,
        active: true
      }
    })
  }

  console.log('Seed completed successfully')
}

seed()
  .catch((e) => {
    console.error('Error during seeding:', e)
    process.exit(1)
  })
  .finally(async () => {
    await prisma.$disconnect()
  }) 