import { User } from '@/types'

export interface AuthState {
  user: User | null
  token: string | null
  isAuthenticated: boolean
  loading: boolean
  error: string | null
}

export interface UiState {
  sidebarOpen: boolean
  theme: 'light' | 'dark'
  notifications: Array<{
    id: string
    type: 'success' | 'error' | 'warning' | 'info'
    message: string
  }>
  loading: {
    [key: string]: boolean
  }
}

export interface RootState {
  auth: AuthState
  ui: UiState
  [key: string]: unknown
} 