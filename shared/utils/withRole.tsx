import { useSession } from "next-auth/react";

export function withRole(allowedRoles: string[]) {
  return function (WrappedComponent: React.ComponentType) {
    return function WithRoleWrapper(
      props: React.ComponentProps<typeof WrappedComponent>,
    ) {
      const { data: session } = useSession();

      if (!session?.user?.role) {
        // Handle no role
        return null;
      }

      if (!allowedRoles.includes(session.user.role)) {
        // Handle unauthorized
        return null;
      }

      return <WrappedComponent {...props} />;
    };
  };
}
