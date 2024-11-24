/**
 * Authentication service for user management and security logging
 * @class AuthService
 */
import { prisma } from "../../lib/prisma";
import { createHash } from "crypto";
import { headers } from "next/headers";
import {
  SecurityEventType,
  SecuritySeverity,
  SecurityEventDetails,
} from "../../types/security";
import { ValidationService } from "./validation.service";

export class AuthService {
  private generateHash(password: string, salt: string): string {
    return createHash("sha256")
      .update(password + salt)
      .digest("hex");
  }

  private generateSalt(): string {
    return createHash("sha256").update(Math.random().toString()).digest("hex");
  }

  private async logSecurityEvent(
    userId: number,
    eventType: SecurityEventType,
    severity: SecuritySeverity,
    details: SecurityEventDetails,
  ) {
    const headersList = await headers();
    const ip =
      (await headersList.get("x-forwarded-for")) ||
      (await headersList.get("x-real-ip"));

    const eventDetails = {
      ...details,
      timestamp: new Date().toISOString(),
    };

    ValidationService.validateSecurityEvent({
      event_type: eventType,
      severity,
      user_id: userId,
      ip_address: ip || null,
      event_details: eventDetails,
      created_at: new Date(),
    });

    await prisma.security_events.create({
      data: {
        event_type: eventType,
        severity,
        user_id: userId,
        ip_address: ip || null,
        event_details: eventDetails,
        created_at: new Date(),
      },
    });
  }

  private createSecurityEventDetails(
    email: string,
    success: boolean,
    reason: string | null,
  ): SecurityEventDetails {
    return {
      email,
      success,
      reason,
      timestamp: new Date().toISOString(),
    };
  }

  async authenticate(email: string, password: string) {
    const user = await prisma.users.findUnique({ where: { email } });

    if (!user) {
      await this.logSecurityEvent(
        0,
        "LOGIN_ATTEMPT",
        "WARNING",
        this.createSecurityEventDetails(email, false, "USER_NOT_FOUND"),
      );
      return null;
    }

    const passwordHash = this.generateHash(password, user.salt);
    if (passwordHash !== user.password_hash) {
      await this.logSecurityEvent(
        user.user_id,
        "LOGIN_ATTEMPT",
        "WARNING",
        this.createSecurityEventDetails(email, false, "INVALID_PASSWORD"),
      );
      return null;
    }

    // Generate session token
    const token = createHash("sha256")
      .update(user.user_id + Date.now().toString())
      .digest("hex");

    const headersList = await headers();
    const ip =
      (await headersList.get("x-forwarded-for")) ||
      (await headersList.get("x-real-ip"));
    const userAgent = await headersList.get("user-agent");

    // Create session with all required fields
    await prisma.user_sessions.create({
      data: {
        session_id: token,
        user_id: user.user_id,
        expires_at: new Date(Date.now() + 24 * 60 * 60 * 1000),
        ip_address: ip || null,
        user_agent: userAgent || null,
        created_at: new Date(),
        is_valid: true,
      },
    });

    // Log successful login
    await this.logSecurityEvent(
      user.user_id,
      "LOGIN_SUCCESS",
      "INFO",
      this.createSecurityEventDetails(email, true, null),
    );

    return { user, token };
  }
}
