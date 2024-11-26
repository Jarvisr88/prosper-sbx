import { NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";

export async function rateLimit(req: Request) {
  const ip = req.headers.get("x-forwarded-for") || "unknown";

  // Check recent requests from this IP
  const recentRequests = await prisma.security_events.count({
    where: {
      ip_address: ip,
      event_time: {
        gte: new Date(Date.now() - 60 * 1000), // Last minute
      },
    },
  });

  // If too many requests, block
  if (recentRequests > 100) {
    // 100 requests per minute
    await prisma.security_events.create({
      data: {
        event_type: "RATE_LIMIT_EXCEEDED",
        ip_address: ip,
        severity: "WARNING",
        event_details: {
          requests: recentRequests,
          timeWindow: "1 minute",
        },
      },
    });

    return NextResponse.json({ error: "Too many requests" }, { status: 429 });
  }

  return NextResponse.next();
}
