import { describe, it, expect, beforeEach, afterEach } from '@jest/globals'
import { GET } from '@/app/api/admin/metrics/route'
import { prisma } from '@/lib/prisma'
import { createMockNextRequest } from '@/__tests__/utils/mockRequest'

jest.mock('@/lib/prisma', () => ({
  prisma: {
    system_metrics_history: {
      findMany: jest.fn(),
      count: jest.fn()
    },
    security_monitoring_log: {
      findFirst: jest.fn()
    }
  }
}))

describe('Metrics API', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  describe('GET /api/admin/metrics', () => {
    it('should get system metrics', async () => {
      const mockMetrics = {
        monitoring: {
          execution_time: new Date(),
          findings: {}
        },
        alerts: 0,
        timestamp: expect.any(Date)
      }

      ;(prisma.security_monitoring_log.findFirst as jest.Mock).mockResolvedValue(mockMetrics.monitoring)
      ;(prisma.system_metrics_history.count as jest.Mock).mockResolvedValue(mockMetrics.alerts)

      const req = createMockNextRequest({
        method: 'GET',
        body: { type: 'system' }
      })

      const response = await GET(req)
      const data = await response.json()

      expect(prisma.security_monitoring_log.findFirst).toHaveBeenCalled()
      expect(data).toMatchObject(mockMetrics)
    })
  })
}) 