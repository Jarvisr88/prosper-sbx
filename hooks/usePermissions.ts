import { useSession } from "next-auth/react";
import { Permission } from "@/types/auth/permissions";

export function usePermissions() {
  const { data: session } = useSession();

  const hasAllPermissions = (requiredPermissions: Permission[]) => {
    if (!session?.user?.permissions) return false;
    const userPermissions = session.user.permissions;
    return requiredPermissions.every((permission) =>
      userPermissions.includes(permission),
    );
  };

  const hasAnyPermission = (requiredPermissions: Permission[]) => {
    if (!session?.user?.permissions) return false;
    const userPermissions = session.user.permissions;
    return requiredPermissions.some((permission) =>
      userPermissions.includes(permission),
    );
  };

  return {
    hasAllPermissions,
    hasAnyPermission,
  };
}
