import { http, HttpResponse } from 'msw'

export const handlers = [
  http.get('/api/test', () => {
    return HttpResponse.json({
      status: 'success',
      message: 'Database connection successful',
      userCount: 5,
      recentUsers: [
        {
          username: 'testuser1',
          email: 'test1@example.com',
          role: 'user',
        },
      ],
    })
  }),

  http.get('/api/admin/users', () => {
    return HttpResponse.json({
      users: [
        {
          user_id: 1,
          username: 'admin',
          email: 'admin@example.com',
          role: 'admin',
          is_active: true,
        },
      ],
    })
  }),
] 