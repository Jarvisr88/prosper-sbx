import { NextRequest, NextResponse } from 'next/server'
import { withProtectedRoute } from '@/middleware/auth/withProtectedRoute'
import { Permission } from '@/types/auth/permissions'
import { prisma } from '@/lib/prisma'

async function handler(req: NextRequest) {
  switch (req.method) {
    case 'GET':
      return await getSettings(req)
    case 'PUT':
      return await updateSettings(req)
    default:
      return NextResponse.json(
        { error: 'Method not allowed' },
        { status: 405 }
      )
  }
}

async function getSettings(req: NextRequest) {
  try {
    const { searchParams } = new URL(req.url)
    const category = searchParams.get('category')

    const settings = await prisma.system_configurations.findMany({
      where: {
        ...(category && { category }),
        is_active: true
      },
      orderBy: {
        config_name: 'asc'
      },
      select: {
        config_id: true,
        config_name: true,
        config_value: true,
        description: true,
        last_modified: true,
        modified_by: true
      }
    })

    return NextResponse.json({ settings })
  } catch (error) {
    console.error('Settings retrieval error:', error)
    return NextResponse.json(
      { error: 'Failed to retrieve settings' },
      { status: 500 }
    )
  }
}

async function updateSettings(req: NextRequest) {
  try {
    const updates = await req.json() as Array<{
      config_id: string;
      value: string;
      old_value: string;
      modified_by?: string;
      reason?: string;
    }>
    const results = await Promise.all(
      updates.map(async (update) => {
        const config = await prisma.system_configurations.update({
          where: { config_id: Number(update.config_id) },
          data: {
            config_value: update.value,
            last_modified: new Date(),
            modified_by: update.modified_by || 'SYSTEM'
          }
        })

        // Create configuration history
        await prisma.configuration_history.create({
          data: {
            config_id: Number(update.config_id),
            previous_value: update.old_value,
            new_value: update.value,
            changed_at: new Date(),
            changed_by: update.modified_by || 'SYSTEM',
            change_reason: update.reason || 'System update'
          }
        })

        return config
      })
    )

    return NextResponse.json({ 
      success: true,
      updated: results.length,
      configs: results
    })
  } catch (error) {
    console.error('Settings update error:', error)
    return NextResponse.json(
      { error: 'Failed to update settings' },
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