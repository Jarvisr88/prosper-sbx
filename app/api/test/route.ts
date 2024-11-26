import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";

export async function GET() {
  try {
    const userCount = await prisma.users.count();
    const users = await prisma.users.findMany({
      select: {
        user_id: true,
        username: true,
        email: true,
      },
    });
    return NextResponse.json({ count: userCount, users });
  } catch (err) {
    console.error("Error fetching data:", err);
    return NextResponse.json(
      { error: "Failed to fetch data" },
      { status: 500 }
    );
  }
}
