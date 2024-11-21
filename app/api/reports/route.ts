import { NextRequest, NextResponse } from 'next/server'
import { withProtectedRoute } from '@/middleware/auth/withProtectedRoute'
import { Permission } from '@/types/auth/permissions'
import { prisma } from '@/lib/prisma'

async function handler(req: NextRequest) {
  if (req.method === 'GET') {
    const { type, startDate, endDate } = await req.json()
    
    switch (type) {
      case 'user_activity':
        return await generateUserActivityReport(startDate, endDate)
      case 'security_audit':
        return await generateSecurityReport(startDate, endDate)
      case 'performance':
        return await generatePerformanceReport(startDate, endDate)
      default:
        return NextResponse.json(
          { error: 'Invalid report type' },
          { status: 400 }
        )
    }
  }
  
  return NextResponse.json(
    { error: 'Method not allowed' },
    { status: 405 }
  )
}

async function generateUserActivityReport(startDate: string, endDate: string) {
  const report = await prisma.$queryRaw`
    SELECT * FROM generate_user_activity_report(${startDate}::timestamp, ${endDate}::timestamp)
  `
  return NextResponse.json({ report })
}

async function generateSecurityReport(startDate: string, endDate: string) {
  const report = await prisma.$queryRaw`
    SELECT * FROM generate_security_audit_report(${startDate}::timestamp, ${endDate}::timestamp)
  `
  return NextResponse.json({ report })
}

async function generatePerformanceReport(startDate: string, endDate: string) {
  const report = await prisma.$queryRaw`
    SELECT * FROM generate_performance_report('system_metrics', ${startDate}::timestamp, ${endDate}::timestamp)
  `
  return NextResponse.json({ report })
}

export const GET = withProtectedRoute(handler, {
  permissions: [Permission.VIEW_REPORTS],
  requireAll: true
}) 