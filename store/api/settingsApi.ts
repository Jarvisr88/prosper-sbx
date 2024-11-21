import { baseApi } from './baseApi'

interface SystemConfig {
  config_id: number
  config_name: string
  config_value: string
  category: string
  description: string
  last_modified: string
  modified_by: string
}

interface ConfigUpdate {
  config_id: number
  value: string
  old_value: string
  modified_by?: string
  reason?: string
}

export const settingsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getSettings: builder.query<SystemConfig[], { category?: string }>({
      query: (params) => ({
        url: '/api/admin/settings',
        method: 'GET',
        params
      }),
      providesTags: ['Settings']
    }),

    updateSettings: builder.mutation<
      { success: boolean; updated: number; configs: SystemConfig[] },
      ConfigUpdate[]
    >({
      query: (updates) => ({
        url: '/api/admin/settings',
        method: 'PUT',
        body: updates
      }),
      invalidatesTags: ['Settings']
    })
  })
})

export const { useGetSettingsQuery, useUpdateSettingsMutation } = settingsApi 