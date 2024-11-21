import { baseApi } from './baseApi'

interface WorkflowExecution {
  execution_id: string
  workflow_id: string
  trigger_source: string
  started_at: string
  completed_at?: string
  status: string
  execution_data?: Record<string, unknown>
  error_details?: Record<string, unknown>
}

export const workflowApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getWorkflowExecutions: builder.query<WorkflowExecution[], void>({
      query: () => ({
        url: '/api/admin/workflows',
        method: 'GET',
        params: { type: 'executions' }
      }),
      providesTags: ['Workflow']
    }),

    getWorkflowPerformance: builder.query<
      { metrics: Record<string, number>; period: string },
      string
    >({
      query: (period) => ({
        url: '/api/admin/workflows',
        method: 'GET',
        params: { type: 'performance', period }
      }),
      providesTags: ['Workflow']
    }),

    getWorkflowErrors: builder.query<WorkflowExecution[], void>({
      query: () => ({
        url: '/api/admin/workflows',
        method: 'GET',
        params: { type: 'errors' }
      }),
      providesTags: ['Workflow']
    })
  })
})

export const {
  useGetWorkflowExecutionsQuery,
  useGetWorkflowPerformanceQuery,
  useGetWorkflowErrorsQuery
} = workflowApi 