import { withAuth } from "next-auth/middleware";

export default withAuth({
  callbacks: {
    authorized({ token }) {
      return !!token;
    },
  },
});

export const config = {
  matcher: [
    "/api/:path*",
    "/dashboard/:path*",
    "/users/:path*",
    "/((?!_next/static|favicon.ico|public|api/auth|login|auth).*)",
  ],
};
