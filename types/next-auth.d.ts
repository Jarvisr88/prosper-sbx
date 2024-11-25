import "next-auth";
import { Permission } from "./auth/permissions";

declare module "next-auth" {
  interface Session {
    user: {
      permissions: Permission[] | undefined;
      id?: string;
      email?: string | null;
      name?: string | null;
      image?: string | null;
      role?: string;
    };
  }

  interface User {
    id: string;
    email: string;
    name?: string;
    image?: string;
    role: string;
    permissions: Permission[];
  }

  interface AdapterUser {
    id: string;
    email: string;
    name?: string | null;
    image?: string | null;
    role: string;
    permissions: Permission[];
  }
}
