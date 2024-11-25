import { NextApiRequest, NextApiResponse } from "next";
import prisma from "../db/prisma";
import { Prisma } from "@prisma/client";
import { randomBytes, createHash } from "crypto";

type ApiResponse<T> = {
  success: boolean;
  data?: T;
  error?: string;
};

// Define proper types based on Prisma schema
type PrismaUser = Prisma.usersGetPayload<{
  select: typeof userSelect;
}>;

const userSelect = {
  user_id: true,
  username: true,
  email: true,
  role: true,
  is_active: true,
  last_login: true,
  created_at: true,
  updated_at: true,
  password_hash: true,
  salt: true,
} as const;

export class UserController {
  private readonly userSelect = userSelect;

  async getUsers(
    req: NextApiRequest,
    res: NextApiResponse<ApiResponse<PrismaUser[]>>,
  ) {
    try {
      const users = await prisma.users.findMany({
        select: this.userSelect,
      });
      return res.status(200).json({ success: true, data: users });
    } catch (error) {
      console.error("Error fetching users:", error);
      return res.status(500).json({
        success: false,
        error: "Failed to fetch users",
      });
    }
  }

  async getUserById(
    req: NextApiRequest,
    res: NextApiResponse<ApiResponse<PrismaUser>>,
  ) {
    try {
      const { id } = req.query;

      if (!id || typeof id !== "string") {
        return res.status(400).json({
          success: false,
          error: "Invalid user ID",
        });
      }

      const user = await prisma.users.findUnique({
        where: { user_id: parseInt(id, 10) },
        select: this.userSelect,
      });

      if (!user) {
        return res.status(404).json({
          success: false,
          error: "User not found",
        });
      }

      return res.status(200).json({ success: true, data: user });
    } catch (error) {
      console.error("Error fetching user:", error);
      return res.status(500).json({
        success: false,
        error: "Failed to fetch user",
      });
    }
  }

  async createUser(
    req: NextApiRequest,
    res: NextApiResponse<ApiResponse<PrismaUser>>,
  ) {
    try {
      const { email, username, role = "USER", is_active = true } = req.body;

      if (!email) {
        return res.status(400).json({
          success: false,
          error: "Email is required",
        });
      }

      const salt = randomBytes(16).toString("hex");
      const password_hash = createHash("sha256")
        .update(salt + "default-password")
        .digest("hex");

      const userData: Prisma.usersCreateInput = {
        email,
        username,
        role,
        is_active,
        salt,
        password_hash,
      };

      const user = await prisma.users.create({
        data: userData,
        select: this.userSelect,
      });

      return res.status(201).json({ success: true, data: user });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError) {
        if (error.code === "P2002") {
          return res.status(400).json({
            success: false,
            error: "A user with this email already exists",
          });
        }
      }
      console.error("Error creating user:", error);
      return res.status(500).json({
        success: false,
        error: "Failed to create user",
      });
    }
  }

  async updateUser(
    req: NextApiRequest,
    res: NextApiResponse<ApiResponse<PrismaUser>>,
  ) {
    try {
      const { id } = req.query;
      const { email, username, role, is_active, last_login } = req.body;

      if (!id || typeof id !== "string") {
        return res.status(400).json({
          success: false,
          error: "Invalid user ID",
        });
      }

      const updateData: Prisma.usersUpdateInput = {};

      if (email !== undefined) updateData.email = email;
      if (username !== undefined) updateData.username = username;
      if (role !== undefined) updateData.role = role;
      if (is_active !== undefined) updateData.is_active = is_active;
      if (last_login !== undefined) updateData.last_login = last_login;

      const user = await prisma.users.update({
        where: { user_id: parseInt(id, 10) },
        data: updateData,
        select: this.userSelect,
      });

      return res.status(200).json({ success: true, data: user });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError) {
        if (error.code === "P2025") {
          return res.status(404).json({
            success: false,
            error: "User not found",
          });
        }
        if (error.code === "P2002") {
          return res.status(400).json({
            success: false,
            error: "Email already in use",
          });
        }
      }
      console.error("Error updating user:", error);
      return res.status(500).json({
        success: false,
        error: "Failed to update user",
      });
    }
  }

  async deleteUser(
    req: NextApiRequest,
    res: NextApiResponse<ApiResponse<void>>,
  ) {
    try {
      const { id } = req.query;

      if (!id || typeof id !== "string") {
        return res.status(400).json({
          success: false,
          error: "Invalid user ID",
        });
      }

      await prisma.users.delete({
        where: { user_id: parseInt(id, 10) },
      });

      return res.status(200).json({ success: true });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError) {
        if (error.code === "P2025") {
          return res.status(404).json({
            success: false,
            error: "User not found",
          });
        }
      }
      console.error("Error deleting user:", error);
      return res.status(500).json({
        success: false,
        error: "Failed to delete user",
      });
    }
  }
}
