import { useSession } from 'next-auth/react'
import { Permission } from '@/types/auth/permissions'

export function usePermissions() {
  const { data: session } = useSession()
  const userRole = session?.user?.role || 'user'

  const hasPermission = (permission: Permission): boolean => {
    return userRole === 'admin'
  }

  const hasAllPermissions = (permissions: Permission[]): boolean => {
    return permissions.every(hasPermission)
  }

  const hasAnyPermission = (permissions: Permission[]): boolean => {
    return permissions.some(hasPermission)
  }

  return {
    hasPermission,
    hasAllPermissions,
    hasAnyPermission,
    userRole
  }
} 