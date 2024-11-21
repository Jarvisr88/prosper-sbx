'use client'

import { useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { useSession } from 'next-auth/react'
import { Permission } from '@/types/auth/permissions'
import { usePermissions } from '@/hooks/usePermissions'

interface ProtectedPageOptions {
  permissions: Permission[]
  requireAll?: boolean
  redirectTo?: string
}

export function withPageProtection<P extends object>(
  WrappedComponent: React.ComponentType<P>,
  options: ProtectedPageOptions
) {
  return function ProtectedPage(props: P) {
    const { data: session, status } = useSession()
    const router = useRouter()
    const { hasAllPermissions, hasAnyPermission } = usePermissions()

    useEffect(() => {
      if (status === 'loading') return

      if (!session) {
        router.push('/auth/signin')
        return
      }

      const hasPermission = options.requireAll
        ? hasAllPermissions(options.permissions)
        : hasAnyPermission(options.permissions)

      if (!hasPermission) {
        router.push(options.redirectTo || '/unauthorized')
      }
    }, [session, status, router, hasAllPermissions, hasAnyPermission])

    if (status === 'loading') {
      return <div>Loading...</div>
    }

    if (!session) {
      return null
    }

    return <WrappedComponent {...props} />
  }
} 