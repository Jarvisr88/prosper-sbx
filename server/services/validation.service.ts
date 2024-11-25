import {
  SecurityEvent,
  SecurityEventType,
  SecuritySeverity,
} from "../../types/security";

export class ValidationService {
  static validateSecurityEvent(event: Partial<SecurityEvent>): boolean {
    // Validate event type
    if (!this.isValidEventType(event.event_type)) {
      throw new Error(`Invalid event type: ${event.event_type}`);
    }

    // Validate severity
    if (!this.isValidSeverity(event.severity)) {
      throw new Error(`Invalid severity: ${event.severity}`);
    }

    // Validate user_id
    if (typeof event.user_id !== "number") {
      throw new Error("User ID must be a number");
    }

    return true;
  }

  private static isValidEventType(type: unknown): type is SecurityEventType {
    return ["LOGIN_ATTEMPT", "LOGIN_SUCCESS", "LOGIN_FAILURE"].includes(
      type as string,
    );
  }

  private static isValidSeverity(
    severity: unknown,
  ): severity is SecuritySeverity {
    return ["INFO", "WARNING", "ERROR"].includes(severity as string);
  }
}
