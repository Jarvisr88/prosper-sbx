import { NextRequest, NextResponse } from 'next/server'
import { withProtectedRoute } from '@/middleware/auth/withProtectedRoute'
import { Permission } from '@/types/auth/permissions'
import { prisma } from '@/lib/prisma'

async function handler(req: NextRequest) {
  if (req.method === 'GET') {
    const users = await prisma.users.findMany({
      select: {
        user_id: true,
        username: true,
        email: true,
        role: true,
        is_active: true,
        last_login: true
      }
    })
    
    return NextResponse.json({ users })
  }
  
  return NextResponse.json(
    { error: 'Method not allowed' },
    { status: 405 }
  )
}

export const GET = withProtectedRoute(handler, {
  permissions: [Permission.READ_USER],
  requireAll: true
}) 