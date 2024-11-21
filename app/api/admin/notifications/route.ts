import { NextRequest, NextResponse } from 'next/server'
import { withProtectedRoute } from '@/middleware/auth/withProtectedRoute'
import { Permission } from '@/types/auth/permissions'
import { prisma } from '@/lib/prisma'

async function handler(req: NextRequest) {
  switch (req.method) {
    case 'GET':
      return await getNotifications(req)
    case 'POST':
      return await createNotification(req)
    case 'PUT':
      return await updateNotification(req)
    default:
      return NextResponse.json(
        { error: 'Method not allowed' },
        { status: 405 }
      )
  }
}

async function getNotifications(req: NextRequest) {
  try {
    const { searchParams } = new URL(req.url)
    const status = searchParams.get('status')
    const type = searchParams.get('type')
    const channel = searchParams.get('channel')

    const notifications = await prisma.notification_history.findMany({
      where: {
        ...(status && { status }),
        ...(type && { notification_type: type }),
        ...(channel && { channel_id: BigInt(channel) })
      },
      include: {
        notification_channels: {
          select: {
            channel_name: true,
            channel_type: true
          }
        },
        notification_templates: {
          select: {
            template_name: true,
            template_type: true
          }
        }
      },
      orderBy: {
        sent_at: 'desc'
      },
      take: 100
    })

    return NextResponse.json({ notifications })
  } catch (error) {
    console.error('Notification retrieval error:', error)
    return NextResponse.json(
      { error: 'Failed to retrieve notifications' },
      { status: 500 }
    )
  }
}

async function createNotification(req: NextRequest) {
  try {
    const data = await req.json()
    const notification = await prisma.notification_history.create({
      data: {
        notification_type: data.type,
        status: 'PENDING',
        recipient: data.recipient,
        subject: data.subject,
        body: data.body,
        metadata: data.metadata || {},
        channel_id: data.channel_id ? BigInt(data.channel_id) : null,
        template_id: data.template_id || null
      },
      include: {
        notification_channels: true,
        notification_templates: true
      }
    })

    return NextResponse.json({ notification })
  } catch (error) {
    console.error('Notification creation error:', error)
    return NextResponse.json(
      { error: 'Failed to create notification' },
      { status: 500 }
    )
  }
}

async function updateNotification(req: NextRequest) {
  try {
    const data = await req.json()
    const notification = await prisma.notification_history.update({
      where: {
        notification_id: BigInt(data.id)
      },
      data: {
        status: data.status,
        sent_at: data.status === 'SENT' ? new Date() : undefined,
        error_details: data.error_details
      }
    })

    return NextResponse.json({ notification })
  } catch (error) {
    console.error('Notification update error:', error)
    return NextResponse.json(
      { error: 'Failed to update notification' },
      { status: 500 }
    )
  }
}

export const GET = withProtectedRoute(handler, {
  permissions: [Permission.MANAGE_SETTINGS],
  requireAll: true
})

export const POST = withProtectedRoute(handler, {
  permissions: [Permission.MANAGE_SETTINGS],
  requireAll: true
})

export const PUT = withProtectedRoute(handler, {
  permissions: [Permission.MANAGE_SETTINGS],
  requireAll: true
}) 