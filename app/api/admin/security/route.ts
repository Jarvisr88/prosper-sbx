import { NextRequest, NextResponse } from 'next/server'
import { withProtectedRoute } from '@/middleware/auth/withProtectedRoute'
import { Permission } from '@/types/auth/permissions'
import { prisma } from '@/lib/prisma'

async function handler(req: NextRequest) {
  if (req.method === 'GET') {
    const { type } = await req.json()
    
    switch (type) {
      case 'active_sessions':
        return await getActiveSessions()
      case 'security_events':
        return await getSecurityEvents()
      case 'failed_attempts':
        return await getFailedAttempts()
      default:
        return NextResponse.json(
          { error: 'Invalid security monitoring type' },
          { status: 400 }
        )
    }
  }

  return NextResponse.json(
    { error: 'Method not allowed' },
    { status: 405 }
  )
}

async function getActiveSessions() {
  const sessions = await prisma.user_sessions.findMany({
    where: {
      is_valid: true,
      expires_at: { gt: new Date() }
    },
    include: {
      users: {
        select: {
          username: true,
          email: true,
          role: true
        }
      }
    }
  })
  return NextResponse.json({ sessions })
}

async function getSecurityEvents() {
  const events = await prisma.security_events.findMany({
    orderBy: { created_at: 'desc' },
    take: 100,
    select: {
      event_id: true,
      event_type: true,
      severity: true,
      user_id: true,
      ip_address: true,
      event_details: true,
      created_at: true
    }
  })
  return NextResponse.json({ events })
}

async function getFailedAttempts() {
  const attempts = await prisma.security_events.findMany({
    where: {
      event_type: 'LOGIN_FAILURE',
      created_at: {
        gte: new Date(Date.now() - 24 * 60 * 60 * 1000)
      }
    },
    orderBy: { created_at: 'desc' },
    select: {
      event_id: true,
      user_id: true,
      ip_address: true,
      event_details: true,
      created_at: true
    }
  })
  return NextResponse.json({ attempts })
}

export const GET = withProtectedRoute(handler, {
  permissions: [Permission.VIEW_AUDIT_LOGS],
  requireAll: true
}) 