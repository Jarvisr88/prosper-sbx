import { useSession } from 'next-auth/react'
import { useRouter } from 'next/router'
import { useEffect } from 'react'

export default function Protected() {
  const { data: session, status } = useSession()
  const router = useRouter()

  useEffect(() => {
    if (status === 'loading') return
    
    if (!session) {
      router.push('/auth/signin')
    }
  }, [session, status, router])

  if (status === 'loading') {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="text-lg">Loading...</div>
      </div>
    )
  }

  if (!session) {
    return null
  }

  return (
    <div className="p-4">
      <h1 className="text-2xl font-bold mb-4">Protected Page</h1>
      <div className="bg-gray-100 p-4 rounded-lg">
        <h2 className="font-semibold mb-2">Session Data:</h2>
        <pre className="whitespace-pre-wrap">
          {JSON.stringify(session, null, 2)}
        </pre>
      </div>
      
      <div className="mt-4">
        <h2 className="font-semibold mb-2">User Info:</h2>
        <p>Email: {session.user.email}</p>
        <p>Name: {session.user.name}</p>
        <p>Role: {session.user.role}</p>
      </div>
    </div>
  )
} 