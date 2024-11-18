export const API_ENDPOINTS = {
  AUTH: {
    LOGIN: '/api/auth/login',
    REGISTER: '/api/auth/register',
    LOGOUT: '/api/auth/logout',
  },
  USERS: {
    ME: '/api/users/me',
    LIST: '/api/users',
    DETAIL: (id: string) => `/api/users/${id}`,
  },
} as const

export const getQueryString = (params: Record<string, string | number | boolean | null | undefined>): string => {
  const searchParams = new URLSearchParams()
  Object.entries(params).forEach(([key, value]) => {
    if (value !== undefined && value !== null) {
      searchParams.append(key, String(value))
    }
  })
  return searchParams.toString()
} 