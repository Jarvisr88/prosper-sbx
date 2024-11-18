import { NextApiRequest, NextApiResponse } from 'next';
import prisma from '../db/prisma';
import { Prisma, User } from '@prisma/client';

type ApiResponse<T> = {
  success: boolean;
  data?: T;
  error?: string;
};

export class UserController {
  private readonly userSelect = {
    id: true,
    email: true,
    name: true,
    role: true,
    employeeId: true,
    isActive: true,
    lastLogin: true,
    createdAt: true,
    updatedAt: true,
    emailVerified: true,
    image: true,
  } as const;

  async getUsers(
    req: NextApiRequest,
    res: NextApiResponse<ApiResponse<User[]>>
  ) {
    try {
      const users = await prisma.user.findMany({
        select: this.userSelect,
      });
      return res.status(200).json({ success: true, data: users });
    } catch (error) {
      console.error('Error fetching users:', error);
      return res.status(500).json({
        success: false,
        error: 'Failed to fetch users',
      });
    }
  }

  async getUserById(
    req: NextApiRequest,
    res: NextApiResponse<ApiResponse<User>>
  ) {
    try {
      const { id } = req.query;

      if (!id || typeof id !== 'string') {
        return res.status(400).json({
          success: false,
          error: 'Invalid user ID',
        });
      }

      const user = await prisma.user.findUnique({
        where: { id },
        select: this.userSelect,
      });

      if (!user) {
        return res.status(404).json({
          success: false,
          error: 'User not found',
        });
      }

      return res.status(200).json({ success: true, data: user });
    } catch (error) {
      console.error('Error fetching user:', error);
      return res.status(500).json({
        success: false,
        error: 'Failed to fetch user',
      });
    }
  }

  async createUser(
    req: NextApiRequest,
    res: NextApiResponse<ApiResponse<User>>
  ) {
    try {
      const { 
        email, 
        name, 
        role = 'USER',
        employeeId,
        isActive = true 
      } = req.body;

      if (!email) {
        return res.status(400).json({
          success: false,
          error: 'Email is required',
        });
      }

      const userData: Prisma.UserCreateInput = {
        email,
        name,
        role,
        employeeId,
        isActive,
      };

      const user = await prisma.user.create({
        data: userData,
        select: this.userSelect,
      });

      return res.status(201).json({ success: true, data: user });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError) {
        if (error.code === 'P2002') {
          return res.status(400).json({
            success: false,
            error: 'A user with this email already exists',
          });
        }
        if (error.code === 'P2003') {
          return res.status(400).json({
            success: false,
            error: 'Invalid employee ID provided',
          });
        }
      }
      console.error('Error creating user:', error);
      return res.status(500).json({
        success: false,
        error: 'Failed to create user',
      });
    }
  }

  async updateUser(
    req: NextApiRequest,
    res: NextApiResponse<ApiResponse<User>>
  ) {
    try {
      const { id } = req.query;
      const {
        email,
        name,
        role,
        employeeId,
        isActive,
        lastLogin,
        emailVerified
      } = req.body;

      if (!id || typeof id !== 'string') {
        return res.status(400).json({
          success: false,
          error: 'Invalid user ID',
        });
      }

      const updateData: Prisma.UserUpdateInput = {};
      
      if (email !== undefined) updateData.email = email;
      if (name !== undefined) updateData.name = name;
      if (role !== undefined) updateData.role = role;
      if (employeeId !== undefined) updateData.employeeId = employeeId;
      if (isActive !== undefined) updateData.isActive = isActive;
      if (lastLogin !== undefined) updateData.lastLogin = lastLogin;
      if (emailVerified !== undefined) updateData.emailVerified = emailVerified;

      const user = await prisma.user.update({
        where: { id },
        data: updateData,
        select: this.userSelect,
      });

      return res.status(200).json({ success: true, data: user });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError) {
        if (error.code === 'P2025') {
          return res.status(404).json({
            success: false,
            error: 'User not found',
          });
        }
        if (error.code === 'P2002') {
          return res.status(400).json({
            success: false,
            error: 'Email already in use',
          });
        }
        if (error.code === 'P2003') {
          return res.status(400).json({
            success: false,
            error: 'Invalid employee ID provided',
          });
        }
      }
      console.error('Error updating user:', error);
      return res.status(500).json({
        success: false,
        error: 'Failed to update user',
      });
    }
  }

  async deleteUser(
    req: NextApiRequest,
    res: NextApiResponse<ApiResponse<void>>
  ) {
    try {
      const { id } = req.query;

      if (!id || typeof id !== 'string') {
        return res.status(400).json({
          success: false,
          error: 'Invalid user ID',
        });
      }

      await prisma.user.delete({
        where: { id },
      });

      return res.status(200).json({ success: true });
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError) {
        if (error.code === 'P2025') {
          return res.status(404).json({
            success: false,
            error: 'User not found',
          });
        }
      }
      console.error('Error deleting user:', error);
      return res.status(500).json({
        success: false,
        error: 'Failed to delete user',
      });
    }
  }
} 