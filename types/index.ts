export interface User {
  id?: string
  username: string
  email: string
  role: string
  isActive?: boolean
  lastLogin?: Date
  createdAt?: Date
  updatedAt?: Date
}

export interface TestResponse {
  status: 'success' | 'error'
  message: string
  userCount: number
  recentUsers?: User[]
  error?: string
} 