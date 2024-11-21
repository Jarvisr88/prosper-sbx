'use client'

import React, { useEffect, useState } from 'react'
import { User, TestResponse } from '@/types'

export default function TestPage() {
  const [status, setStatus] = useState<string>('Loading...')
  const [error, setError] = useState<string | null>(null)
  const [users, setUsers] = useState<User[]>([])
  const [isClient, setIsClient] = useState(false)

  useEffect(() => {
    setIsClient(true)
    fetch('/api/test')
      .then(res => {
        if (!res.ok) throw new Error(`HTTP error! status: ${res.status}`)
        return res.json()
      })
      .then((data: TestResponse) => {
        setStatus(`${data.message} - Users in database: ${data.userCount}`)
        setUsers(data.recentUsers || [])
      })
      .catch(err => {
        console.error('Fetch error:', err)
        setError(err.message)
        setStatus('Error')
      })
  }, [])

  if (!isClient) {
    return <div>Loading...</div>
  }

  return (
    <div className="p-4">
      <h1 className="text-2xl font-bold mb-4">Database Connection Test</h1>
      <div className="mb-4">Status: {status}</div>
      {error && (
        <div className="text-red-500">Error: {error}</div>
      )}
      {users.length > 0 && (
        <div className="mt-4">
          <h2 className="text-xl font-semibold mb-2">Recent Users:</h2>
          <ul className="list-disc pl-5">
            {users.map((user, index) => (
              <li key={`${user.email}-${index}`}>
                {user.username} ({user.email}) - {user.role}
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  )
} 