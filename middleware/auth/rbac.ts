import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'
import { getToken } from 'next-auth/jwt'

export interface RBACOptions {
  allowedRoles: string[]
  redirectTo?: string
}

export async function withRBAC(
  req: NextRequest,
  options: RBACOptions
) {
  try {
    const token = await getToken({ req })
    
    if (!token) {
      return NextResponse.redirect(new URL('/auth/signin', req.url))
    }

    const userRole = token.role as string
    
    if (!options.allowedRoles.includes(userRole)) {
      return options.redirectTo 
        ? NextResponse.redirect(new URL(options.redirectTo, req.url))
        : NextResponse.json(
            { error: 'Insufficient permissions' },
            { status: 403 }
          )
    }

    return NextResponse.next()
  } catch (error) {
    console.error('RBAC Error:', error)
    return NextResponse.json(
      { error: 'Authorization error' },
      { status: 500 }
    )
  }
} 