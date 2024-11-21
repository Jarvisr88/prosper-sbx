import { expect, describe, it } from '@jest/globals'
import uiReducer, {
  toggleSidebar,
  setTheme,
  addNotification,
  removeNotification,
  setLoading
} from '@/store/slices/uiSlice'
import type { UiState } from '@/store/types'

describe('ui slice', () => {
  const initialState: UiState = {
    sidebarOpen: true,
    theme: 'light',
    notifications: [],
    loading: {}
  }

  it('should handle initial state', () => {
    const result = uiReducer(undefined, { type: 'unknown' })
    expect(result).toEqual(initialState)
  })

  it('should handle toggleSidebar', () => {
    const result = uiReducer(initialState, toggleSidebar())
    expect(result.sidebarOpen).toBe(false)

    const result2 = uiReducer(result, toggleSidebar())
    expect(result2.sidebarOpen).toBe(true)
  })

  it('should handle setTheme', () => {
    const result = uiReducer(initialState, setTheme('dark'))
    expect(result.theme).toBe('dark')

    const result2 = uiReducer(result, setTheme('light'))
    expect(result2.theme).toBe('light')
  })

  it('should handle addNotification', () => {
    const notification = {
      type: 'success' as const,
      message: 'Test notification'
    }
    const result = uiReducer(initialState, addNotification(notification))
    expect(result.notifications).toHaveLength(1)
    expect(result.notifications[0]).toMatchObject(notification)
    expect(result.notifications[0].id).toBeDefined()
  })

  it('should handle removeNotification', () => {
    const state: UiState = {
      ...initialState,
      notifications: [
        { id: '1', type: 'success', message: 'Test 1' },
        { id: '2', type: 'error', message: 'Test 2' }
      ]
    }
    const result = uiReducer(state, removeNotification('1'))
    expect(result.notifications).toHaveLength(1)
    expect(result.notifications[0].id).toBe('2')
  })

  it('should handle setLoading', () => {
    const result = uiReducer(
      initialState,
      setLoading({ key: 'testOperation', value: true })
    )
    expect(result.loading.testOperation).toBe(true)

    const result2 = uiReducer(
      result,
      setLoading({ key: 'testOperation', value: false })
    )
    expect(result2.loading.testOperation).toBe(false)
  })
}) 