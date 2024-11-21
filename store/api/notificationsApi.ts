import { baseApi } from './baseApi'

interface Notification {
  notification_id: string
  notification_type: string
  status: string
  recipient?: string
  subject?: string
  body?: string
  sent_at?: string
  error_details?: Record<string, unknown>
  metadata?: Record<string, unknown>
  channel?: {
    channel_name: string
    channel_type: string
  }
  template?: {
    template_name: string
    template_type: string
  }
}

interface NotificationCreate {
  type: string
  recipient: string
  subject?: string
  body?: string
  channel_id?: string
  template_id?: string
  metadata?: Record<string, unknown>
}

export const notificationsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getNotifications: builder.query<
      Notification[],
      { status?: string; type?: string; channel?: string }
    >({
      query: (params) => ({
        url: '/api/admin/notifications',
        method: 'GET',
        params
      }),
      providesTags: ['Notifications']
    }),

    createNotification: builder.mutation<Notification, NotificationCreate>({
      query: (data) => ({
        url: '/api/admin/notifications',
        method: 'POST',
        body: data
      }),
      invalidatesTags: ['Notifications']
    }),

    updateNotificationStatus: builder.mutation<
      Notification,
      { id: string; status: string; error_details?: Record<string, unknown> }
    >({
      query: (data) => ({
        url: '/api/admin/notifications',
        method: 'PUT',
        body: data
      }),
      invalidatesTags: ['Notifications']
    })
  })
})

export const {
  useGetNotificationsQuery,
  useCreateNotificationMutation,
  useUpdateNotificationStatusMutation
} = notificationsApi 