import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'
import { getToken } from 'next-auth/jwt'

export function withAuth(handler: (request: NextRequest) => Promise<NextResponse>) {
  return async function (request: NextRequest) {
    try {
      const token = await getToken({ 
        req: request, 
        secret: process.env.NEXTAUTH_SECRET 
      })

      if (!token) {
        return new NextResponse(
          JSON.stringify({ 
            error: 'Authentication required',
            redirect: '/auth/signin'
          }),
          { 
            status: 401, 
            headers: { 'Content-Type': 'application/json' } 
          }
        )
      }

      // Add token to request for downstream use
      request.headers.set('x-user-id', token.sub as string)
      request.headers.set('x-user-role', token.role as string)

      return await handler(request)
    } catch (err) {
      console.error('Auth error:', err)
      return new NextResponse(
        JSON.stringify({ 
          error: 'Invalid session',
          redirect: '/auth/signin'
        }),
        { 
          status: 403, 
          headers: { 'Content-Type': 'application/json' } 
        }
      )
    }
  }
}

// Optional: Role-based middleware
export function withRole(role: string | string[]) {
  return function(handler: (request: NextRequest) => Promise<NextResponse>) {
    return withAuth(async (request: NextRequest) => {
      const userRole = request.headers.get('x-user-role')
      const roles = Array.isArray(role) ? role : [role]

      if (!userRole || !roles.includes(userRole)) {
        return new NextResponse(
          JSON.stringify({ error: 'Insufficient permissions' }),
          { status: 403, headers: { 'Content-Type': 'application/json' } }
        )
      }

      return await handler(request)
    })
  }
} 