export interface UserRole {
  ADMIN: 'ADMIN'
  USER: 'USER'
  GUEST: 'GUEST'
}

export interface User {
  id: string
  email: string
  name: string | null
  role: keyof UserRole
  createdAt: Date
  updatedAt: Date
}

export interface Session {
  user: User
  expires: Date
} 