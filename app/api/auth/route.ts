import { NextResponse } from "next/server";
import { AuthService } from "@/server/services/auth.service";

const authService = new AuthService();

export async function POST(request: Request) {
  try {
    const { email, password } = await request.json();

    const result = await authService.authenticate(email, password);
    if (!result) {
      return NextResponse.json(
        { error: "Invalid credentials" },
        { status: 401 },
      );
    }

    const { user, token } = result;

    return NextResponse.json({
      user: {
        id: user.user_id,
        username: user.username,
        email: user.email,
        role: user.role,
      },
      token,
    });
  } catch (error) {
    console.error("Authentication error:", error);
    return NextResponse.json(
      { error: "Authentication failed" },
      { status: 500 },
    );
  }
}
