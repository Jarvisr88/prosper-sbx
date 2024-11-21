import { NextRequest, NextResponse } from 'next/server'
import { withProtectedRoute } from '@/middleware/auth/withProtectedRoute'
import { Permission } from '@/types/auth/permissions'
import { prisma } from '@/lib/prisma'

async function handler(req: NextRequest) {
  switch (req.method) {
    case 'GET':
      return await getRoles()
    case 'POST':
      return await createRole(req)
    case 'PUT':
      return await updateRole(req)
    case 'DELETE':
      return await deleteRole(req)
    default:
      return NextResponse.json(
        { error: 'Method not allowed' },
        { status: 405 }
      )
  }
}

async function getRoles() {
  const roles = await prisma.access_control.findMany({
    where: { active: true },
    select: {
      access_id: true,
      role_name: true,
      permissions: true,
      description: true
    }
  })
  return NextResponse.json({ roles })
}

async function createRole(req: NextRequest) {
  try {
    const data = await req.json()
    const role = await prisma.access_control.create({
      data: {
        role_name: data.role_name,
        permissions: data.permissions,
        description: data.description,
        active: true
      }
    })
    return NextResponse.json({ role })
  } catch (error) {
    console.error('Create role error:', error)
    return NextResponse.json(
      { error: 'Failed to create role' },
      { status: 500 }
    )
  }
}

async function updateRole(req: NextRequest) {
  try {
    const { access_id, ...data } = await req.json()
    const role = await prisma.access_control.update({
      where: { access_id },
      data
    })
    return NextResponse.json({ role })
  } catch (error) {
    console.error('Update role error:', error)
    return NextResponse.json(
      { error: 'Failed to update role' },
      { status: 500 }
    )
  }
}

async function deleteRole(req: NextRequest) {
  try {
    const { access_id } = await req.json()
    await prisma.access_control.update({
      where: { access_id },
      data: { active: false }
    })
    return NextResponse.json({ success: true })
  } catch (error) {
    console.error('Delete role error:', error)
    return NextResponse.json(
      { error: 'Failed to delete role' },
      { status: 500 }
    )
  }
}

export const GET = withProtectedRoute(handler, {
  permissions: [Permission.MANAGE_ROLES],
  requireAll: true
})

export const POST = withProtectedRoute(handler, {
  permissions: [Permission.MANAGE_ROLES],
  requireAll: true
})

export const PUT = withProtectedRoute(handler, {
  permissions: [Permission.MANAGE_ROLES],
  requireAll: true
})

export const DELETE = withProtectedRoute(handler, {
  permissions: [Permission.MANAGE_ROLES],
  requireAll: true
}) 