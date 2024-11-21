import { baseApi } from './baseApi'

interface Metric {
  metric_name: string
  metric_value: number
  metric_type: string
  collection_time: string
  granularity: string
  dimensions: Record<string, unknown>
}

interface MetricQuery {
  type?: string
  period?: '24h' | '7d' | '30d'
}

export const metricsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getMetrics: builder.query<Metric[], MetricQuery>({
      query: (params) => ({
        url: '/api/admin/metrics',
        method: 'GET',
        params
      }),
      providesTags: ['Metrics']
    }),

    recordMetric: builder.mutation<
      Metric,
      {
        name: string
        value: number
        type: string
        granularity?: string
        dimensions?: Record<string, unknown>
      }
    >({
      query: (data) => ({
        url: '/api/admin/metrics',
        method: 'POST',
        body: data
      }),
      invalidatesTags: ['Metrics']
    }),

    getSystemHealth: builder.query<
      {
        metrics: {
          activeUsers: number
          activeSessions: number
          securityEvents: number
          recentWorkflows: number
        }
        timestamp: string
      },
      void
    >({
      query: () => ({
        url: '/api/admin/health',
        method: 'GET',
        params: { metric: 'system' }
      }),
      providesTags: ['Metrics']
    })
  })
})

export const {
  useGetMetricsQuery,
  useRecordMetricMutation,
  useGetSystemHealthQuery
} = metricsApi 