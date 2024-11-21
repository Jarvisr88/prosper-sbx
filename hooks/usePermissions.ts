import { useSession } from 'next-auth/react'
import { Permission, DEFAULT_ROLE_PERMISSIONS } from '@/types/auth/permissions'

export function usePermissions() {
  const { data: session } = useSession()
  const userRole = session?.user?.role || 'user'

  const hasPermission = (permission: Permission): boolean => {
    const rolePermissions = DEFAULT_ROLE_PERMISSIONS[userRole as keyof typeof DEFAULT_ROLE_PERMISSIONS]
    return rolePermissions?.includes(permission) || false
  }

  const hasAnyPermission = (permissions: Permission[]): boolean => {
    return permissions.some(hasPermission)
  }

  const hasAllPermissions = (permissions: Permission[]): boolean => {
    return permissions.every(hasPermission)
  }

  return {
    hasPermission,
    hasAnyPermission,
    hasAllPermissions,
    userRole
  }
} 