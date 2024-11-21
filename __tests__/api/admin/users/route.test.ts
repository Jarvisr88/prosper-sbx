import { describe, it, expect, beforeEach, afterEach } from '@jest/globals'
import { POST, PUT, DELETE } from '@/app/api/admin/users/manage/route'
import { prisma } from '@/lib/prisma'
import { createMockNextRequest } from '@/__tests__/utils/mockRequest'

// Mock the auth middleware
jest.mock('@/middleware/auth/withProtectedRoute', () => ({
  withProtectedRoute: (handler: (req: Request) => Promise<Response>) => handler
}))

// Mock Prisma
jest.mock('@/lib/prisma', () => ({
  prisma: {
    users: {
      findMany: jest.fn(),
      create: jest.fn(),
      update: jest.fn(),
      delete: jest.fn()
    }
  }
}))

describe('Users API', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  describe('POST /api/admin/users/manage', () => {
    it('should create a new user', async () => {
      const newUser = {
        username: 'testuser',
        email: 'test@example.com',
        role: 'user'
      }

      const mockPrismaResponse = { ...newUser, user_id: 1 }
      ;(prisma.users.create as jest.Mock).mockResolvedValue(mockPrismaResponse)

      const req = createMockNextRequest({
        method: 'POST',
        body: newUser
      })

      const response = await POST(req)
      const data = await response.json()

      expect(prisma.users.create).toHaveBeenCalledWith({
        data: newUser
      })
      expect(response.status).toBe(200)
      expect(data).toEqual({
        user: mockPrismaResponse
      })
    })

    it('should handle creation errors', async () => {
      const error = new Error('Database error')
      ;(prisma.users.create as jest.Mock).mockRejectedValue(error)

      const req = createMockNextRequest({
        method: 'POST',
        body: {}
      })

      const response = await POST(req)
      const data = await response.json()

      expect(response.status).toBe(500)
      expect(data).toEqual({
        error: 'Failed to create user'
      })
    })
  })

  describe('PUT /api/admin/users/manage', () => {
    it('should update an existing user', async () => {
      const updateData = {
        id: 1,
        username: 'updateduser',
        email: 'updated@example.com'
      }

      const mockPrismaResponse = { ...updateData, user_id: 1 }
      ;(prisma.users.update as jest.Mock).mockResolvedValue(mockPrismaResponse)

      const req = createMockNextRequest({
        method: 'PUT',
        body: updateData
      })

      const response = await PUT(req)
      const data = await response.json()

      expect(prisma.users.update).toHaveBeenCalledWith({
        where: { user_id: updateData.id },
        data: expect.objectContaining({
          username: updateData.username,
          email: updateData.email
        })
      })
      expect(response.status).toBe(200)
      expect(data).toEqual({ user: mockPrismaResponse })
    })
  })

  describe('DELETE /api/admin/users/manage', () => {
    it('should delete a user', async () => {
      const userId = 1
      ;(prisma.users.delete as jest.Mock).mockResolvedValue({ user_id: userId })

      const req = createMockNextRequest({
        method: 'DELETE',
        body: { id: userId }
      })

      const response = await DELETE(req)
      const data = await response.json()

      expect(prisma.users.delete).toHaveBeenCalledWith({
        where: { user_id: userId }
      })
      expect(response.status).toBe(200)
      expect(data).toEqual({ success: true })
    })
  })
}) 