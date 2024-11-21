import { describe, it, expect, beforeEach, afterEach } from '@jest/globals'
import { GET } from '@/app/api/admin/security/route'
import { prisma } from '@/lib/prisma'
import { createMockNextRequest } from '@/__tests__/utils/mockRequest'

jest.mock('@/lib/prisma', () => ({
  prisma: {
    user_sessions: {
      findMany: jest.fn()
    },
    security_events: {
      findMany: jest.fn()
    }
  }
}))

describe('Security API', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  describe('GET /api/admin/security', () => {
    it('should get active sessions', async () => {
      const mockSessions = [
        {
          session_id: '1',
          user_id: 1,
          is_valid: true,
          users: {
            username: 'test',
            email: 'test@example.com',
            role: 'user'
          }
        }
      ]

      ;(prisma.user_sessions.findMany as jest.Mock).mockResolvedValue(mockSessions)

      const req = createMockNextRequest({
        method: 'GET',
        body: { type: 'active_sessions' }
      })

      const response = await GET(req)
      const data = await response.json()

      expect(prisma.user_sessions.findMany).toHaveBeenCalled()
      expect(data).toEqual({ sessions: mockSessions })
    })

    it('should get security events', async () => {
      const mockEvents = [
        {
          event_id: '1',
          event_type: 'LOGIN',
          severity: 'INFO',
          created_at: new Date()
        }
      ]

      ;(prisma.security_events.findMany as jest.Mock).mockResolvedValue(mockEvents)

      const req = createMockNextRequest({
        method: 'GET',
        body: { type: 'security_events' }
      })

      const response = await GET(req)
      const data = await response.json()

      expect(prisma.security_events.findMany).toHaveBeenCalled()
      expect(data).toEqual({ events: mockEvents })
    })
  })
}) 