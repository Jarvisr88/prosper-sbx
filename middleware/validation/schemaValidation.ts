import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";

// Define base types for validation
type ValidationResult = {
  success: boolean;
  data?: unknown;
  error?: string;
  details?: z.ZodIssue[];
};

// Validation schemas for different models
const performanceScoreSchema = z.object({
  initial_self_score: z.number().min(1).max(5),
  self_score: z.number().min(1).max(5),
  manager_score: z.number().min(1).max(5),
  challenge_score: z.number().min(1).max(5),
  concurrent_score: z.number().min(1).max(5),
});

const projectAssignmentSchema = z
  .object({
    start_date: z.coerce.date(),
    end_date: z.coerce.date(),
    priority: z.number().min(1).max(5),
  })
  .refine(
    (data: { start_date: Date; end_date: Date }) =>
      data.start_date < data.end_date,
    {
      message: "End date must be after start date",
    }
  );

const metricAlertSchema = z.object({
  threshold_value: z.number(),
  alert_type: z.enum(["PERFORMANCE", "SYSTEM", "SECURITY"]),
  frequency: z.enum(["HOURLY", "DAILY", "WEEKLY"]),
});

// Validation middleware factory
export function createValidationMiddleware(schema: z.ZodSchema) {
  return async function validationMiddleware(
    req: NextRequest,
    next: () => Promise<NextResponse>
  ) {
    try {
      const body = await req.json();
      await schema.parseAsync(body);
      return next();
    } catch (error) {
      if (error instanceof z.ZodError) {
        return NextResponse.json(
          {
            success: false,
            error: "Validation failed",
            details: error.errors,
          } satisfies ValidationResult,
          { status: 400 }
        );
      }

      const errorMessage =
        error instanceof Error ? error.message : "Internal server error";
      return NextResponse.json(
        {
          success: false,
          error: errorMessage,
        } satisfies ValidationResult,
        { status: 500 }
      );
    }
  };
}

// Export type-safe schemas for reuse
export const Schemas = {
  performanceScore: performanceScoreSchema,
  projectAssignment: projectAssignmentSchema,
  metricAlert: metricAlertSchema,
} as const;

// Export type-safe validation middleware instances
export const Validators = {
  performanceScore: createValidationMiddleware(performanceScoreSchema),
  projectAssignment: createValidationMiddleware(projectAssignmentSchema),
  metricAlert: createValidationMiddleware(metricAlertSchema),
} as const;

// Export inferred types from schemas
export type PerformanceScore = z.infer<typeof performanceScoreSchema>;
export type ProjectAssignment = z.infer<typeof projectAssignmentSchema>;
export type MetricAlert = z.infer<typeof metricAlertSchema>;
