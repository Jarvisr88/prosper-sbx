import { render, screen } from "@testing-library/react";
import { useSession } from "next-auth/react";
import { ProtectedComponent } from "@/client/components/auth/ProtectedComponent";
import { Permission } from "@/types/auth/permissions";
import { usePermissions } from "@/hooks/usePermissions";

// Mock the hooks
jest.mock("next-auth/react");
jest.mock("@/hooks/usePermissions");

describe("ProtectedComponent", () => {
  const mockUseSession = useSession as jest.Mock;
  const mockUsePermissions = usePermissions as jest.Mock;

  beforeEach(() => {
    mockUseSession.mockReturnValue({
      data: { user: { role: "user" } },
      status: "authenticated",
    });

    mockUsePermissions.mockReturnValue({
      hasAllPermissions: jest.fn().mockReturnValue(true),
      hasAnyPermission: jest.fn().mockReturnValue(true),
    });
  });

  it("renders children when user has required permissions", () => {
    render(
      <ProtectedComponent permissions={[Permission.READ_USER]}>
        <div>Protected Content</div>
      </ProtectedComponent>,
    );

    expect(screen.getByText("Protected Content")).toBeInTheDocument();
  });

  it("renders nothing when user lacks required permissions", () => {
    mockUsePermissions.mockReturnValue({
      hasAllPermissions: jest.fn().mockReturnValue(false),
      hasAnyPermission: jest.fn().mockReturnValue(false),
    });

    render(
      <ProtectedComponent permissions={[Permission.READ_USER]}>
        <div>Protected Content</div>
      </ProtectedComponent>,
    );

    expect(screen.queryByText("Protected Content")).not.toBeInTheDocument();
  });

  it("handles requireAll prop correctly", () => {
    mockUsePermissions.mockReturnValue({
      hasAllPermissions: jest.fn().mockReturnValue(false),
      hasAnyPermission: jest.fn().mockReturnValue(true),
    });

    render(
      <ProtectedComponent
        permissions={[Permission.READ_USER, Permission.CREATE_USER]}
        requireAll={true}
      >
        <div>Protected Content</div>
      </ProtectedComponent>,
    );

    expect(screen.queryByText("Protected Content")).not.toBeInTheDocument();
  });

  it("shows loading state when session is loading", () => {
    mockUseSession.mockReturnValue({
      data: null,
      status: "loading",
    });

    render(
      <ProtectedComponent permissions={[Permission.READ_USER]}>
        <div>Protected Content</div>
      </ProtectedComponent>,
    );

    expect(screen.queryByText("Protected Content")).not.toBeInTheDocument();
  });
});
