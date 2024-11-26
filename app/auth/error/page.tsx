'use client'

import { Suspense } from 'react'
import { useSearchParams } from 'next/navigation'

function ErrorContent() {
  const searchParams = useSearchParams()
  const error = searchParams.get('error')

  return (
    <div className="flex min-h-screen flex-col items-center justify-center">
      <div className="w-full max-w-md space-y-8">
        <div className="text-center">
          <h2 className="mt-6 text-3xl font-bold text-red-600">Authentication Error</h2>
          <p className="mt-2">
            {error === 'Configuration' 
              ? 'There is a problem with the server configuration.'
              : error || 'An error occurred during authentication.'}
          </p>
          <button
            onClick={() => window.location.href = '/auth/signin'}
            className="mt-4 px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700"
          >
            Try Again
          </button>
        </div>
      </div>
    </div>
  )
}

export default function ErrorPage() {
  return (
    <Suspense fallback={<div>Loading...</div>}>
      <ErrorContent />
    </Suspense>
  )
} 