import { createApi, fetchBaseQuery } from '@reduxjs/toolkit/query/react'
import type { RootState } from '../types'

export const baseApi = createApi({
  reducerPath: 'api',
  baseQuery: fetchBaseQuery({
    baseUrl: '/api',
    prepareHeaders: (headers, { getState }) => {
      const state = getState() as RootState
      const token = state.auth?.token
      if (token) {
        headers.set('authorization', `Bearer ${token}`)
      }
      return headers
    }
  }),
  tagTypes: [
    'User',
    'Role',
    'Audit',
    'Security',
    'Metrics',
    'Workflow',
    'Settings',
    'Notifications',
    'Permissions'
  ],
  endpoints: () => ({})
})