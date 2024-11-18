import { withRole } from '../shared/utils/withRole';

function AdminPage() {
  return (
    <div>
      <h1>Admin Dashboard</h1>
      {/* Admin content */}
    </div>
  );
}

export default withRole(AdminPage, ['ADMIN']); 