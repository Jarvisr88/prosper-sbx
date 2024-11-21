import { expect, describe, it } from '@jest/globals'
import authReducer, {
  setCredentials,
  clearCredentials,
  setLoading,
  setError
} from '@/store/slices/authSlice'
import type { AuthState } from '@/store/types'

describe('auth slice', () => {
  const initialState: AuthState = {
    user: null,
    token: null,
    isAuthenticated: false,
    loading: true,
    error: null
  }

  it('should handle initial state', () => {
    const result = authReducer(undefined, { type: 'unknown' })
    expect(result).toEqual(initialState)
  })

  it('should handle setCredentials', () => {
    const user = { username: 'test', id: '1', email: 'test@example.com', role: 'user' }
    const token = 'test-token'
    const result = authReducer(initialState, setCredentials({ user, token }))
    expect(result).toEqual({
      user,
      token,
      isAuthenticated: true,
      loading: false,
      error: null
    })
  })

  it('should handle clearCredentials', () => {
    const state: AuthState = {
      user: { username: 'test', id: '1', email: 'test@example.com', role: 'user' },
      token: 'test-token',
      isAuthenticated: true,
      loading: false,
      error: null
    }
    const result = authReducer(state, clearCredentials())
    expect(result).toEqual(initialState)
  })

  it('should handle setLoading', () => {
    const result = authReducer(initialState, setLoading(false))
    expect(result.loading).toBe(false)
  })

  it('should handle setError', () => {
    const errorMessage = 'Test error'
    const result = authReducer(initialState, setError(errorMessage))
    expect(result.error).toBe(errorMessage)
    expect(result.loading).toBe(false)
  })
}) 
