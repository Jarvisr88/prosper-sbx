import { prisma } from '@/lib/prisma'
import { NextResponse } from 'next/server'
import type { TestResponse } from '@/types'

export async function GET() {
  try {
    const userCount = await prisma.users.count()
    const users = await prisma.users.findMany({
      take: 5,
      select: {
        username: true,
        email: true,
        role: true
      }
    })
    
    const response: TestResponse = {
      status: 'success',
      message: 'Database connection successful',
      userCount,
      recentUsers: users
    }
    
    return NextResponse.json(response)
  } catch (error) {
    console.error('Database connection error:', error)
    const errorResponse: TestResponse = {
      status: 'error',
      message: 'Database connection failed',
      userCount: 0,
      error: error instanceof Error ? error.message : 'Unknown error'
    }
    return NextResponse.json(errorResponse, { status: 500 })
  }
} 