import { withAuth } from '@/utils/withAuth';

function ProtectedPage() {
  return (
    <div>
      <h1>Protected Content</h1>
      {/* Protected content */}
    </div>
  );
}

export default withAuth(ProtectedPage); 