import { baseApi } from './baseApi'

interface AuditLog {
  entity_type: string
  entity_id: string
  action_type: string
  action_date: string
  old_values: Record<string, unknown>
  new_values: Record<string, unknown>
  performed_by: string
}

interface AuditQuery {
  entity_type?: string
  start_date?: string
  end_date?: string
}

export const auditApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getAuditLogs: builder.query<AuditLog[], AuditQuery>({
      query: (params) => ({
        url: '/api/admin/audit',
        method: 'GET',
        params: {
          entity_type: params.entity_type,
          start_date: params.start_date,
          end_date: params.end_date
        }
      }),
      providesTags: ['Audit']
    }),
    
    getAuditSummary: builder.query<
      { entity_type: string; action_count: number }[],
      { start_date: string; end_date: string }
    >({
      query: (params) => ({
        url: '/api/admin/audit/summary',
        method: 'GET',
        params
      }),
      providesTags: ['Audit']
    }),

    getEntityHistory: builder.query<
      AuditLog[],
      { entity_type: string; entity_id: string }
    >({
      query: ({ entity_type, entity_id }) => ({
        url: '/api/admin/audit/history',
        method: 'GET',
        params: { entity_type, entity_id }
      }),
      providesTags: (result, error, arg) => [
        { type: 'Audit', id: `${arg.entity_type}:${arg.entity_id}` }
      ]
    })
  })
})

export const {
  useGetAuditLogsQuery,
  useGetAuditSummaryQuery,
  useGetEntityHistoryQuery
} = auditApi 