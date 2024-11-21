'use client'

import { useSession } from 'next-auth/react'

export default function AuthStatus() {
  const { data: session, status } = useSession()

  if (status === 'loading') {
    return <div>Loading...</div>
  }

  return (
    <div>
      {session ? (
        <div>Signed in as {session.user?.email}</div>
      ) : (
        <div>Not signed in</div>
      )}
    </div>
  )
} 