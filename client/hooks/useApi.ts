import { useState } from 'react'
import { ApiResponse } from '@/shared/types/common'

interface UseApiOptions<T> {
  onSuccess?: (data: T) => void
  onError?: (error: string) => void
}

export function useApi<T>() {
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const fetchData = async (
    endpoint: string,
    options: RequestInit = {},
    apiOptions: UseApiOptions<T> = {}
  ): Promise<T | null> => {
    try {
      setLoading(true)
      setError(null)

      const response = await fetch(endpoint, {
        ...options,
        headers: {
          'Content-Type': 'application/json',
          ...options.headers,
        },
      })

      const data = await response.json() as ApiResponse<T>

      if (!response.ok) {
        throw new Error(data.error || 'An error occurred')
      }

      if (data.data && apiOptions.onSuccess) {
        apiOptions.onSuccess(data.data)
      }

      return data.data || null
    } catch (err) {
      const message = err instanceof Error ? err.message : 'An error occurred'
      setError(message)
      apiOptions.onError?.(message)
      return null
    } finally {
      setLoading(false)
    }
  }

  return {
    loading,
    error,
    fetchData,
  }
} 