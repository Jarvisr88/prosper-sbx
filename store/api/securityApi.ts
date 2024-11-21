import { baseApi } from './baseApi'

interface SecurityEvent {
  event_id: string
  event_type: string
  severity: string
  user_id?: number
  ip_address?: string
  event_details?: Record<string, unknown>
  created_at: string
}

interface Session {
  session_id: string
  user_id: number
  created_at: string
  expires_at: string
  is_valid: boolean
  ip_address?: string
  user_agent?: string
  users?: {
    username: string
    email: string
    role: string
  }
}

export const securityApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getSecurityEvents: builder.query<SecurityEvent[], void>({
      query: () => ({
        url: '/api/admin/security',
        method: 'GET',
        body: { type: 'security_events' }
      }),
      providesTags: ['Security']
    }),
    getActiveSessions: builder.query<Session[], void>({
      query: () => ({
        url: '/api/admin/security',
        method: 'GET',
        body: { type: 'active_sessions' }
      }),
      providesTags: ['Security']
    }),
    getFailedAttempts: builder.query<SecurityEvent[], void>({
      query: () => ({
        url: '/api/admin/security',
        method: 'GET',
        body: { type: 'failed_attempts' }
      }),
      providesTags: ['Security']
    })
  })
})

export const {
  useGetSecurityEventsQuery,
  useGetActiveSessionsQuery,
  useGetFailedAttemptsQuery
} = securityApi 