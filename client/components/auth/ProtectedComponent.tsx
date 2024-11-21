'use client'

import React from 'react'
import { usePermissions } from '@/hooks/usePermissions'
import { Permission } from '@/types/auth/permissions'

interface ProtectedComponentProps {
  children: React.ReactNode
  permissions: Permission[]
  requireAll?: boolean
  fallback?: React.ReactNode
}

export function ProtectedComponent({
  children,
  permissions,
  requireAll = false,
  fallback = null
}: ProtectedComponentProps) {
  const { hasAllPermissions, hasAnyPermission } = usePermissions()

  const hasAccess = requireAll
    ? hasAllPermissions(permissions)
    : hasAnyPermission(permissions)

  if (!hasAccess) {
    return fallback
  }

  return <>{children}</>
} 