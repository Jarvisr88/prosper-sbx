"use client";

import { signIn } from "next-auth/react";

export default function LoginPage() {
  const handleSignIn = async () => {
    try {
      await signIn("google", {
        callbackUrl: "/",
        redirect: true,
      });
    } catch (error) {
      console.error("Sign in error:", error);
    }
  };

  return (
    <div className="flex min-h-screen items-center justify-center">
      <button
        onClick={handleSignIn}
        className="rounded bg-blue-500 px-4 py-2 text-white hover:bg-blue-600 transition-colors"
      >
        Sign in with Google
      </button>
    </div>
  );
}
