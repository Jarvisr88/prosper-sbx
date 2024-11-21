import { NextRequest, NextResponse } from 'next/server'
import { withProtectedRoute } from '@/middleware/auth/withProtectedRoute'
import { Permission } from '@/types/auth/permissions'
import { prisma } from '@/lib/prisma'

async function handler(req: NextRequest) {
  switch (req.method) {
    case 'GET':
      return await getConfigurations()
    case 'PUT':
      return await updateConfiguration(req)
    default:
      return NextResponse.json(
        { error: 'Method not allowed' },
        { status: 405 }
      )
  }
}

async function getConfigurations() {
  const configs = await prisma.system_configurations.findMany({
    where: { is_active: true },
    orderBy: { config_name: 'asc' }
  })
  return NextResponse.json({ configs })
}

async function updateConfiguration(req: NextRequest) {
  try {
    const { config_id, config_value } = await req.json()
    
    const config = await prisma.system_configurations.update({
      where: { config_id },
      data: {
        config_value,
        last_modified: new Date(),
        modified_by: 'SYSTEM' // TODO: Get from session
      }
    })

    // Create configuration history
    await prisma.configuration_history.create({
      data: {
        config_id,
        previous_value: config.config_value,
        new_value: config_value,
        changed_at: new Date(),
        changed_by: 'SYSTEM' // TODO: Get from session
      }
    })
    return NextResponse.json({ config })
  } catch (error: unknown) {
    console.error('Error updating configuration:', error)
    return NextResponse.json(
      { error: 'Failed to update configuration' },
      { status: 500 }
    )
  }
}

export const GET = withProtectedRoute(handler, {
  permissions: [Permission.MANAGE_SETTINGS],
  requireAll: true
})

export const PUT = withProtectedRoute(handler, {
  permissions: [Permission.MANAGE_SETTINGS],
  requireAll: true
}) 