import "next-auth";
import { Permission } from "./auth/permissions";

declare module "next-auth" {
  interface Session {
    user: {
      id: string;
      role: string;
      username?: string;
      is_active?: boolean;
      user_id?: number;
    } & DefaultSession["user"];
  }

  interface User {
    role: string;
    username?: string;
    is_active?: boolean;
    user_id?: number;
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
