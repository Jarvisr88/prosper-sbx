import { useSession } from 'next-auth/react';
import { useRouter } from 'next/router';
import { useEffect } from 'react';
import { ComponentType } from 'react';

export function withRole<P extends JSX.IntrinsicAttributes>(
  WrappedComponent: ComponentType<P>,
  allowedRoles: string[]
) {
  return function WithRoleComponent(props: P) {
    const { data: session, status } = useSession();
    const router = useRouter();

    useEffect(() => {
      if (status === 'unauthenticated') {
        router.replace('/auth/signin');
      } else if (session?.user && !allowedRoles.includes(session.user.role)) {
        router.replace('/unauthorized');
      }
    }, [status, session, router]);

    if (status === 'loading') {
      return <div>Loading...</div>;
    }

    if (!session || !allowedRoles.includes(session.user.role)) {
      return null;
    }

    return <WrappedComponent {...props} />;
  };
} 