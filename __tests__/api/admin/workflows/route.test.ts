import { describe, it, expect, beforeEach, afterEach } from '@jest/globals'
import { GET } from '@/app/api/admin/workflows/route'
import { prisma } from '@/lib/prisma'
import { createMockNextRequest } from '@/__tests__/utils/mockRequest'

jest.mock('@/lib/prisma', () => ({
  prisma: {
    workflow_executions: {
      findMany: jest.fn()
    },
    workflow_step_logs: {
      findMany: jest.fn()
    },
    workflow_definitions: {
      findMany: jest.fn()
    }
  }
}))

describe('Workflows API', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  describe('GET /api/admin/workflows', () => {
    it('should get workflow executions', async () => {
      const mockExecutions = [
        {
          execution_id: '1',
          workflow_id: '1',
          trigger_source: 'SCHEDULED',
          started_at: new Date(),
          status: 'COMPLETED',
          execution_data: {}
        }
      ]

      ;(prisma.workflow_executions.findMany as jest.Mock).mockResolvedValue(mockExecutions)

      const req = createMockNextRequest({
        method: 'GET',
        body: { type: 'executions' }
      })

      const response = await GET(req)
      const data = await response.json()

      expect(prisma.workflow_executions.findMany).toHaveBeenCalled()
      expect(data).toEqual({ executions: mockExecutions })
    })

    it('should get workflow performance metrics', async () => {
      const expectedMetrics = {
        metrics: {
          total_executions: 100,
          success_rate: 95.5,
          average_duration: 120,
          error_rate: 4.5
        },
        period: '24h'
      }

      ;(prisma.workflow_executions.findMany as jest.Mock).mockResolvedValue([
        { status: 'COMPLETED', execution_duration: 120 }
      ])

      const req = createMockNextRequest({
        method: 'GET',
        body: { type: 'performance', period: '24h' }
      })

      const response = await GET(req)
      const data = await response.json()

      expect(prisma.workflow_executions.findMany).toHaveBeenCalled()
      expect(data).toMatchObject({
        metrics: expect.any(Object),
        period: expectedMetrics.period
      })
    })

    it('should get workflow errors', async () => {
      const mockErrors = [
        {
          execution_id: '1',
          workflow_id: '1',
          status: 'ERROR',
          error_details: { message: 'Test error' },
          started_at: new Date()
        }
      ]

      ;(prisma.workflow_executions.findMany as jest.Mock).mockResolvedValue(mockErrors)

      const req = createMockNextRequest({
        method: 'GET',
        body: { type: 'errors' }
      })

      const response = await GET(req)
      const data = await response.json()

      expect(prisma.workflow_executions.findMany).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({
            status: 'ERROR'
          })
        })
      )
      expect(data).toEqual({ errors: mockErrors })
    })

    it('should handle invalid request type', async () => {
      const req = createMockNextRequest({
        method: 'GET',
        body: { type: 'invalid' }
      })

      const response = await GET(req)
      const data = await response.json()

      expect(response.status).toBe(400)
      expect(data).toEqual({
        error: 'Invalid workflow monitoring type'
      })
    })

    it('should handle database errors', async () => {
      const error = new Error('Database error')
      ;(prisma.workflow_executions.findMany as jest.Mock).mockRejectedValue(error)

      const req = createMockNextRequest({
        method: 'GET',
        body: { type: 'executions' }
      })

      const response = await GET(req)
      const data = await response.json()

      expect(response.status).toBe(500)
      expect(data).toEqual({
        error: 'Failed to retrieve workflow data'
      })
    })
  })
}) 