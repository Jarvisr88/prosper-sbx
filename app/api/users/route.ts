import { NextResponse } from "next/server";
import prisma from "@/server/db/prisma";
import { ApiResponse } from "@/shared/types/common";
import { createHash } from "crypto";

type UserResponse = {
  user_id: number;
  username: string;
  email: string;
  role: string;
  is_active: boolean | null;
  last_login: Date | null;
  created_at: Date | null;
  updated_at: Date | null;
};

type CreateUserBody = {
  email: string;
  name?: string;
  role?: string;
};

type UpdateUserBody = {
  email?: string;
  name?: string;
  role?: string;
  is_active?: boolean;
};

// GET all users
export async function GET(): Promise<
  NextResponse<ApiResponse<UserResponse[]>>
> {
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

    return NextResponse.json({
      data: users,
      status: 200,
    });
  } catch (error) {
    console.error("Users fetch error:", error);
    return NextResponse.json(
      {
        error: "Failed to fetch users",
        status: 500,
      },
      { status: 500 },
    );
  }
}

// POST create user
export async function POST(
  request: Request,
): Promise<NextResponse<ApiResponse<UserResponse>>> {
  try {
    const body: CreateUserBody = await request.json();

    // Generate salt and hash for new user
    const salt = createHash("sha256")
      .update(Math.random().toString())
      .digest("hex");
    const password_hash = createHash("sha256")
      .update(salt + "default-password")
      .digest("hex");

    const user = await prisma.users.create({
      data: {
        email: body.email,
        username: body.name || "",
        role: body.role || "USER",
        password_hash,
        salt,
      },
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

    return NextResponse.json({
      data: user,
      status: 201,
    });
  } catch (error) {
    console.error("User creation error:", error);
    return NextResponse.json(
      {
        error: "Failed to create user",
        status: 500,
      },
      { status: 500 },
    );
  }
}

// PUT update user
export async function PUT(
  request: Request,
): Promise<NextResponse<ApiResponse<UserResponse>>> {
  try {
    const { searchParams } = new URL(request.url);
    const id = searchParams.get("id");

    if (!id) {
      return NextResponse.json(
        {
          error: "User ID is required",
          status: 400,
        },
        { status: 400 },
      );
    }

    const body: UpdateUserBody = await request.json();

    const user = await prisma.users.update({
      where: { user_id: parseInt(id, 10) },
      data: body,
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

    return NextResponse.json({
      data: user,
      status: 200,
    });
  } catch (error) {
    console.error("User update error:", error);
    return NextResponse.json(
      {
        error: "Failed to update user",
        status: 500,
      },
      { status: 500 },
    );
  }
}

// DELETE user
export async function DELETE(
  request: Request,
): Promise<NextResponse<ApiResponse<UserResponse>>> {
  try {
    const { searchParams } = new URL(request.url);
    const id = searchParams.get("id");

    if (!id) {
      return NextResponse.json(
        {
          error: "User ID is required",
          status: 400,
        },
        { status: 400 },
      );
    }

    const user = await prisma.users.update({
      where: { user_id: parseInt(id, 10) },
      data: { is_active: false },
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

    return NextResponse.json({
      data: user,
      status: 200,
    });
  } catch (error) {
    console.error("User deletion error:", error);
    return NextResponse.json(
      {
        error: "Failed to delete user",
        status: 500,
      },
      { status: 500 },
    );
  }
}
