import { Permission } from "@/types/auth/permissions";
import { Session } from "next-auth";

export const mockSession: Session = {
  user: {
    id: "1",
    name: "Test User",
    email: "test@example.com",
    image: null,
    role: "user",
    permissions: [] as Permission[],
  },
  expires: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
};
