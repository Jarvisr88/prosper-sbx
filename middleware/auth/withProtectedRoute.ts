import { NextRequest, NextResponse } from 'next/server'
import { getToken } from 'next-auth/jwt'
import { Permission } from '@/types/auth/permissions'
import { DEFAULT_ROLE_PERMISSIONS } from '@/types/auth/permissions'

interface ProtectedRouteOptions {
  permissions: Permission[]
  requireAll?: boolean
}

export function withProtectedRoute(
  handler: (req: NextRequest) => Promise<NextResponse>,
  options: ProtectedRouteOptions
) {
  return async function protectedHandler(req: NextRequest) {
    try {
      const token = await getToken({ req })
      
      if (!token) {
        return NextResponse.json(
          { error: 'Unauthorized' },
          { status: 401 }
        )
      }

      const userRole = token.role as string
      const rolePermissions = DEFAULT_ROLE_PERMISSIONS[userRole as keyof typeof DEFAULT_ROLE_PERMISSIONS]

      const hasPermission = options.requireAll
        ? options.permissions.every(p => rolePermissions.includes(p))
        : options.permissions.some(p => rolePermissions.includes(p))

      if (!hasPermission) {
        return NextResponse.json(
          { error: 'Insufficient permissions' },
          { status: 403 }
        )
      }

      return handler(req)
    } catch (error) {
      console.error('Protected route error:', error)
      return NextResponse.json(
        { error: 'Internal server error' },
        { status: 500 }
      )
    }
  }
} 