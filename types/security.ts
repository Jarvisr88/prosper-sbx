import { Prisma } from "@prisma/client";

export type SecurityEventType =
  | "LOGIN_ATTEMPT"
  | "LOGIN_SUCCESS"
  | "LOGIN_FAILURE";
export type SecuritySeverity = "INFO" | "WARNING" | "ERROR";

export interface SecurityEvent {
  event_type: SecurityEventType;
  severity: SecuritySeverity;
  user_id: number;
  ip_address: string | null;
  event_details: Prisma.JsonObject;
  created_at: Date;
}

export interface SecurityEventDetails {
  email: string | null;
  success: boolean;
  reason: string | null;
  timestamp: string | null;
  [key: string]: string | boolean | null;
}
