import { baseApi } from './baseApi'
import type { User } from '@/types'

export const userApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getUsers: builder.query<User[], void>({
      query: () => '/api/admin/users',
      providesTags: ['User']
    }),
    getUserById: builder.query<User, string>({
      query: (id) => `/api/admin/users/${id}`,
      providesTags: (_result, _error, id) => [{ type: 'User', id }]
    }),
    createUser: builder.mutation<User, Partial<User>>({
      query: (body) => ({
        url: '/api/admin/users/manage',
        method: 'POST',
        body
      }),
      invalidatesTags: ['User']
    }),
    updateUser: builder.mutation<User, { id: string; data: Partial<User> }>({
      query: ({ id, data }) => ({
        url: `/api/admin/users/manage`,
        method: 'PUT',
        body: { id, ...data }
      }),
      invalidatesTags: (_result, _error, { id }) => [
        'User',
        { type: 'User', id }
      ]
    }),
    deleteUser: builder.mutation<void, string>({
      query: (id) => ({
        url: `/api/admin/users/manage`,
        method: 'DELETE',
        body: { id }
      }),
      invalidatesTags: ['User']
    })
  })
})

export const {
  useGetUsersQuery,
  useGetUserByIdQuery,
  useCreateUserMutation,
  useUpdateUserMutation,
  useDeleteUserMutation
} = userApi 