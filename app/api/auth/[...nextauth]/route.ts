import NextAuth, { NextAuthOptions } from "next-auth"
import { prisma } from "@/lib/prisma"
import GoogleProvider from "next-auth/providers/google"
import crypto from 'crypto'

declare module "next-auth" {
  interface Session {
    user: {
      id?: string
      name?: string | null
      email?: string | null
      image?: string | null
      role?: string
    }
  }

  interface User {
    role?: string
    id?: string
  }
}

export const authOptions: NextAuthOptions = {
  providers: [
    GoogleProvider({
      clientId: process.env.GOOGLE_CLIENT_ID!,
      clientSecret: process.env.GOOGLE_CLIENT_SECRET!,
    }),
  ],
  callbacks: {
    async signIn({ profile }) {
      if (!profile?.email) return false
      try {
        await prisma.users.upsert({
          where: { email: profile.email },
          update: {
            last_login: new Date(),
          },
          create: {
            email: profile.email,
            username: profile.email.split('@')[0] || 'user',
            password_hash: crypto.randomBytes(16).toString('hex'),
            salt: crypto.randomBytes(16).toString('hex'),
            role: 'user',
          },
        })
        return true
      } catch (error) {
        console.error('Sign in error:', error)
        return false
      }
    },
    async session({ session, token }) {
      return {
        ...session,
        user: {
          ...session.user,
          role: token.role,
          id: token.userId?.toString()
        }
      }
    },
    async jwt({ token, account, profile }) {
      if (account && profile?.email) {
        const user = await prisma.users.findUnique({
          where: { email: profile.email }
        })
        if (user) {
          token.role = user.role
          token.userId = user.user_id
        }
      }
      return token
    }
  },
  pages: {
    signIn: '/auth/signin',
    error: '/auth/error',
  },
  session: {
    strategy: 'jwt' as const
  }
}

const handler = NextAuth(authOptions)
export { handler as GET, handler as POST }
