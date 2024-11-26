import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";

export async function GET() {
  try {
    const users = await prisma.users.findMany({
      select: {
        user_id: true,
        username: true,
        email: true,
        role: true,
        is_active: true,
        last_login: true,
        created_at: true,
        updated_at: true,
      },
    });
    return NextResponse.json({ users });
  } catch (err) {
    console.error("Error fetching users:", err);
    return NextResponse.json(
      { error: "Failed to fetch users" },
      { status: 500 }
    );
  }
}
