import NextAuth from "next-auth";
import GoogleProvider from "next-auth/providers/google";
import { PrismaAdapter } from "@next-auth/prisma-adapter";
import { prisma } from "@/lib/prisma";
import { randomBytes } from "crypto";

const handler = NextAuth({
  adapter: PrismaAdapter(prisma),
  providers: [
    GoogleProvider({
      clientId: process.env.GOOGLE_CLIENT_ID!,
      clientSecret: process.env.GOOGLE_CLIENT_SECRET!,
    }),
  ],
  callbacks: {
    async signIn({ user }) {
      // Check if user exists in our legacy system
      const existingUser = await prisma.users.findUnique({
        where: { email: user.email! },
      });

      if (!existingUser) {
        // Create new user in our system
        await prisma.users.create({
          data: {
            email: user.email!,
            username: user.name || user.email!.split("@")[0],
            role: "USER",
            is_active: true,
            password_hash: "", // Empty for OAuth users
            salt: randomBytes(16).toString("hex"), // Generate salt but don't use it for OAuth
          },
        });
      }

      return true;
    },
    async session({ session }) {
      if (session.user) {
        const dbUser = await prisma.users.findUnique({
          where: { email: session.user.email! },
        });

        if (dbUser) {
          session.user.id = dbUser.user_id.toString();
          session.user.role = dbUser.role;
        }
      }
      return session;
    },
  },
});

export { handler as GET, handler as POST };
