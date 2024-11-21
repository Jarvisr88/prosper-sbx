import { NextRequest, NextResponse } from 'next/server'
import { withProtectedRoute } from '@/middleware/auth/withProtectedRoute'
import { Permission } from '@/types/auth/permissions'
import { prisma } from '@/lib/prisma'

async function handler(req: NextRequest) {
  if (req.method === 'GET') {
    const { searchParams } = new URL(req.url)
    const type = searchParams.get('type')
    const period = searchParams.get('period') || '24h'
    
    switch (type) {
      case 'executions':
        return await getWorkflowExecutions(period)
      case 'performance':
        return await getWorkflowPerformance(period)
      case 'errors':
        return await getWorkflowErrors(period)
      default:
        return NextResponse.json(
          { error: 'Invalid workflow monitoring type' },
          { status: 400 }
        )
    }
  }

  return NextResponse.json(
    { error: 'Method not allowed' },
    { status: 405 }
  )
}

async function getWorkflowExecutions(period: string) {
  try {
    const hours = period === '7d' ? 168 : period === '1d' ? 24 : 1
    const startDate = new Date(Date.now() - hours * 60 * 60 * 1000)

    const executions = await prisma.workflow_executions.findMany({
      where: {
        started_at: {
          gte: startDate
        }
      },
      include: {
        automation_workflows: {
          select: {
            workflow_name: true,
            workflow_type: true
          }
        },
        workflow_step_logs: {
          select: {
            step_name: true,
            status: true,
            started_at: true,
            completed_at: true,
            error_details: true
          }
        }
      },
      orderBy: {
        started_at: 'desc'
      }
    })

    return NextResponse.json({
      executions,
      period,
      timestamp: new Date()
    })
  } catch (error) {
    console.error('Workflow executions error:', error)
    return NextResponse.json(
      { error: 'Failed to retrieve workflow executions' },
      { status: 500 }
    )
  }
}

async function getWorkflowPerformance(period: string) {
  try {
    const hours = period === '7d' ? 168 : period === '1d' ? 24 : 1
    const startDate = new Date(Date.now() - hours * 60 * 60 * 1000)

    const metrics = await prisma.workflow_executions.groupBy({
      by: ['status'],
      where: {
        started_at: {
          gte: startDate
        }
      },
      _count: {
        execution_id: true
      }
    })

    return NextResponse.json({
      metrics,
      period,
      timestamp: new Date()
    })
  } catch (error) {
    console.error('Workflow performance error:', error)
    return NextResponse.json(
      { error: 'Failed to retrieve workflow performance metrics' },
      { status: 500 }
    )
  }
}

async function getWorkflowErrors(period: string) {
  try {
    const hours = period === '7d' ? 168 : period === '1d' ? 24 : 1
    const startDate = new Date(Date.now() - hours * 60 * 60 * 1000)

    const errors = await prisma.workflow_executions.findMany({
      where: {
        started_at: {
          gte: startDate
        },
        status: 'ERROR',
        error_details: {
          not: {
            equals: null
          }
        }
      },
      select: {
        execution_id: true,
        workflow_id: true,
        started_at: true,
        error_details: true,
        automation_workflows: {
          select: {
            workflow_name: true
          }
        }
      },
      orderBy: {
        started_at: 'desc'
      }
    })

    return NextResponse.json({
      errors,
      period,
      timestamp: new Date()
    })
  } catch (error) {
    console.error('Workflow errors retrieval error:', error)
    return NextResponse.json(
      { error: 'Failed to retrieve workflow errors' },
      { status: 500 }
    )
  }
}

export const GET = withProtectedRoute(handler, {
  permissions: [Permission.MANAGE_SETTINGS],
  requireAll: true
}) 