'use client'

import { useEffect, useState } from 'react'
import { useApi } from '@/client/hooks/useApi'
import { User } from '@/shared/types/auth'
import { API_ENDPOINTS } from '@/shared/utils/api'

export default function UsersPage() {
  const { loading, error, fetchData } = useApi<User[]>()
  const [users, setUsers] = useState<User[]>([])

  useEffect(() => {
    const loadUsers = async () => {
      const result = await fetchData(API_ENDPOINTS.USERS.LIST, {}, {
        onSuccess: () => {
          console.log('Users loaded successfully')
        },
        onError: (error) => {
          console.error('Failed to load users:', error)
        }
      })
      if (result) setUsers(result)
    }

    loadUsers()
  }, [fetchData])

  if (loading) return <div>Loading...</div>
  if (error) return <div>Error: {error}</div>

  return (
    <div className="p-4">
      <h1 className="text-2xl font-bold mb-4">Users</h1>
      <div className="grid gap-4">
        {users.map((user) => (
          <div key={user.id} className="p-4 border rounded">
            <h2 className="font-bold">{user.name}</h2>
            <p>{user.email}</p>
            <p>Role: {user.role}</p>
          </div>
        ))}
      </div>
    </div>
  )
} 