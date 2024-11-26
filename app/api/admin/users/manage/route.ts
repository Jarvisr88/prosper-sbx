/* eslint-disable @typescript-eslint/no-unused-vars */
import { NextRequest, NextResponse } from "next/server";
import { withProtectedRoute } from "@/middleware/auth/withProtectedRoute";
import { Permission } from "@/types/auth/permissions";
import { prisma } from "@/lib/prisma";

async function handler(req: NextRequest) {
  switch (req.method) {
    case "POST":
      return handleCreate(req);
    case "PUT":
      return handleUpdate(req);
    case "DELETE":
      return handleDelete(req);
    default:
      return NextResponse.json(
        { error: "Method not allowed" },
        { status: 405 }
      );
  }
}

async function handleCreate(req: NextRequest) {
  try {
    const data = await req.json();
    const user = await prisma.users.create({ data });
    return NextResponse.json({ user });
  } catch (error) {
    return NextResponse.json(
      { error: "Failed to create user" },
      { status: 500 }
    );
  }
}

async function handleUpdate(req: NextRequest) {
  try {
    const data = await req.json();
    const { id, ...updateData } = data;
    const user = await prisma.users.update({
      where: { user_id: id },
      data: updateData,
    });
    return NextResponse.json({ user });
  } catch (error) {
    return NextResponse.json(
      { error: "Failed to update user" },
      { status: 500 }
    );
  }
}

async function handleDelete(req: NextRequest) {
  try {
    const { id } = await req.json();
    await prisma.users.delete({
      where: { user_id: id },
    });
    return NextResponse.json({ success: true });
  } catch (error) {
    return NextResponse.json(
      { error: "Failed to delete user" },
      { status: 500 }
    );
  }
}

export const POST = withProtectedRoute(handler, {
  permissions: [Permission.CREATE_USER],
  requireAll: true,
});

export const PUT = withProtectedRoute(handler, {
  permissions: [Permission.UPDATE_USER],
  requireAll: true,
});

export const DELETE = withProtectedRoute(handler, {
  permissions: [Permission.DELETE_USER],
  requireAll: true,
});
