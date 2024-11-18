import { NextResponse } from 'next/server'
import prisma from '@/server/db/prisma'
import { ApiResponse } from '@/shared/types/common'

type UserResponse = {
  id: string
  email: string | null
  name: string | null
  role: string
  createdAt: Date
  updatedAt: Date
  isActive: boolean
}

type CreateUserBody = {
  email: string
  name?: string
  role?: string
}

type UpdateUserBody = {
  email?: string
  name?: string
  role?: string
  isActive?: boolean
}

// GET all users
export async function GET(): Promise<NextResponse<ApiResponse<UserResponse[]>>> {
  try {
    const users = await prisma.user.findMany({
      select: {
        id: true,
        email: true,
        name: true,
        role: true,
        createdAt: true,
        updatedAt: true,
        isActive: true,
      },
    })

    return NextResponse.json({
      data: users,
      status: 200,
    })
  } catch (error) {
    console.error('Users fetch error:', error)
    return NextResponse.json(
      {
        error: 'Failed to fetch users',
        status: 500,
      },
      { status: 500 }
    )
  }
}

// POST create user
export async function POST(
  request: Request
): Promise<NextResponse<ApiResponse<UserResponse>>> {
  try {
    const body: CreateUserBody = await request.json()

    const user = await prisma.user.create({
      data: {
        email: body.email,
        name: body.name,
        role: body.role || 'USER',
      },
      select: {
        id: true,
        email: true,
        name: true,
        role: true,
        createdAt: true,
        updatedAt: true,
        isActive: true,
      },
    })

    return NextResponse.json({
      data: user,
      status: 201,
    })
  } catch (error) {
    console.error('User creation error:', error)
    return NextResponse.json(
      {
        error: 'Failed to create user',
        status: 500,
      },
      { status: 500 }
    )
  }
}

// PUT update user
export async function PUT(
  request: Request
): Promise<NextResponse<ApiResponse<UserResponse>>> {
  try {
    const { searchParams } = new URL(request.url)
    const id = searchParams.get('id')
    
    if (!id) {
      return NextResponse.json(
        {
          error: 'User ID is required',
          status: 400,
        },
        { status: 400 }
      )
    }

    const body: UpdateUserBody = await request.json()

    const user = await prisma.user.update({
      where: { id },
      data: body,
      select: {
        id: true,
        email: true,
        name: true,
        role: true,
        createdAt: true,
        updatedAt: true,
        isActive: true,
      },
    })

    return NextResponse.json({
      data: user,
      status: 200,
    })
  } catch (error) {
    console.error('User update error:', error)
    return NextResponse.json(
      {
        error: 'Failed to update user',
        status: 500,
      },
      { status: 500 }
    )
  }
}

// DELETE user
export async function DELETE(
  request: Request
): Promise<NextResponse<ApiResponse<UserResponse>>> {
  try {
    const { searchParams } = new URL(request.url)
    const id = searchParams.get('id')
    
    if (!id) {
      return NextResponse.json(
        {
          error: 'User ID is required',
          status: 400,
        },
        { status: 400 }
      )
    }

    const user = await prisma.user.update({
      where: { id },
      data: { isActive: false },
      select: {
        id: true,
        email: true,
        name: true,
        role: true,
        createdAt: true,
        updatedAt: true,
        isActive: true,
      },
    })

    return NextResponse.json({
      data: user,
      status: 200,
    })
  } catch (error) {
    console.error('User deletion error:', error)
    return NextResponse.json(
      {
        error: 'Failed to delete user',
        status: 500,
      },
      { status: 500 }
    )
  }
} 