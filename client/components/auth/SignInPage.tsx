'use client'

import React from 'react'
import { signIn } from 'next-auth/react'
import { useSearchParams } from 'next/navigation'

export default function SignInPage() {
  const searchParams = useSearchParams()
  const error = searchParams.get('error')
  const callbackUrl = searchParams.get('callbackUrl') || '/'

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 py-12 px-4 sm:px-6 lg:px-8">
      <div className="max-w-md w-full space-y-8">
        <div>
          <h2 className="mt-6 text-center text-3xl font-extrabold text-gray-900">
            Sign in to Prosper
          </h2>
          {error && (
            <div className="mt-2 text-center text-red-600">
              {error === 'Callback' ? 'Error signing in' : error}
            </div>
          )}
        </div>
        <div className="mt-8 space-y-6">
          <button
            onClick={() => signIn('google', { callbackUrl })}
            className="group relative w-full flex justify-center py-2 px-4 border border-transparent text-sm font-medium rounded-md text-white bg-indigo-600 hover:bg-indigo-700"
          >
            Sign in with Google
          </button>
        </div>
      </div>
    </div>
  )
} 