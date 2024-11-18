import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'

export function withAuth(handler: (request: NextRequest) => Promise<NextResponse>) {
  return async function (request: NextRequest) {
    const token = request.headers.get('Authorization')?.replace('Bearer ', '')
    
    if (!token) {
      return new NextResponse(
        JSON.stringify({ error: 'Authentication required' }),
        { status: 401, headers: { 'Content-Type': 'application/json' } }
      )
    }

    try {
      // Add your token verification logic here
      return await handler(request)
    } catch (err) {
      console.error('Auth error:', err)
      return new NextResponse(
        JSON.stringify({ error: 'Invalid token' }),
        { status: 403, headers: { 'Content-Type': 'application/json' } }
      )
    }
  }
} 