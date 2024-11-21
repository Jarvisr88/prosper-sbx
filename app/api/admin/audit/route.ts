import { NextRequest, NextResponse } from 'next/server'
import { withProtectedRoute } from '@/middleware/auth/withProtectedRoute'
import { Permission } from '@/types/auth/permissions'
import { prisma } from '@/lib/prisma'

async function handler(req: NextRequest) {
  if (req.method === 'GET') {
    const { searchParams } = new URL(req.url)
    const entity_type = searchParams.get('entity_type')
    const start_date = searchParams.get('start_date')
    const end_date = searchParams.get('end_date')
    
    return await getAuditLogs({
      entity_type: entity_type || undefined,
      start_date: start_date ? new Date(start_date) : undefined,
      end_date: end_date ? new Date(end_date) : undefined
    })
  }

  return NextResponse.json(
    { error: 'Method not allowed' },
    { status: 405 }
  )
}

interface AuditQuery {
  entity_type?: string
  start_date?: Date
  end_date?: Date
}

async function getAuditLogs(query: AuditQuery) {
  try {
    const where = {
      ...(query.entity_type && { entity_type: query.entity_type }),
      ...(query.start_date && query.end_date && {
        action_date: {
          gte: query.start_date,
          lte: query.end_date
        }
      })
    }

    const logs = await prisma.audit_log.findMany({
      where,
      orderBy: {
        action_date: 'desc'
      },
      select: {
        entity_type: true,
        entity_id: true,
        action_type: true,
        action_date: true,
        old_values: true,
        new_values: true,
        performed_by: true
      },
      take: 100
    })

    return NextResponse.json({ logs })
  } catch (error) {
    console.error('Audit log error:', error)
    return NextResponse.json(
      { error: 'Failed to retrieve audit logs' },
      { status: 500 }
    )
  }
}

export const GET = withProtectedRoute(handler, {
  permissions: [Permission.VIEW_AUDIT_LOGS],
  requireAll: true
}) 