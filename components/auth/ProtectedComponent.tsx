'use client'

import React from 'react'
import { Permission } from '@/types/auth/permissions'
import { usePermissions } from '@/hooks/usePermissions'

interface ProtectedComponentProps {
  children: React.ReactNode
  permissions: Permission | Permission[]
  requireAll?: boolean
  fallback?: React.ReactNode
}

export function ProtectedComponent({
  children,
  permissions,
  requireAll = false,
  fallback = null
}: ProtectedComponentProps) {
  const { hasPermission, hasAllPermissions, hasAnyPermission } = usePermissions()

  const hasAccess = Array.isArray(permissions)
    ? requireAll
      ? hasAllPermissions(permissions)
      : hasAnyPermission(permissions)
    : hasPermission(permissions)

  if (!hasAccess) {
    return fallback
  }

  return <>{children}</>
} 