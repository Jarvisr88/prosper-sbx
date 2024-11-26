import { NextRequest, NextResponse } from "next/server";
import { withProtectedRoute } from "@/middleware/auth/withProtectedRoute";
import { Permission } from "@/types/auth/permissions";
import { prisma } from "@/lib/prisma";

async function handler(req: NextRequest) {
  if (req.method === "GET") {
    const { searchParams } = new URL(req.url);
    const type = searchParams.get("type");

    switch (type) {
      case "recent":
        return await getRecentEvents();
      case "summary":
        return await getEventsSummary();
      default:
        return NextResponse.json(
          { error: "Invalid request type" },
          { status: 400 }
        );
    }
  }

  return NextResponse.json({ error: "Method not allowed" }, { status: 405 });
}

async function getRecentEvents() {
  try {
    const events = await prisma.security_events.findMany({
      take: 10,
      orderBy: { event_time: "desc" },
      select: {
        event_id: true,
        event_type: true,
        event_time: true,
        ip_address: true,
        user_id: true,
        event_details: true,
        severity: true,
      },
    });

    return NextResponse.json({ events });
  } catch (error) {
    console.error("Error fetching recent events:", error);
    return NextResponse.json(
      { error: "Failed to fetch recent events" },
      { status: 500 }
    );
  }
}

async function getEventsSummary() {
  try {
    const events = await prisma.security_events.findMany({
      where: {
        event_time: {
          gte: new Date(Date.now() - 24 * 60 * 60 * 1000),
        },
      },
      orderBy: { event_time: "desc" },
      select: {
        event_id: true,
        event_type: true,
        event_time: true,
        severity: true,
        event_details: true,
      },
    });

    return NextResponse.json({ events });
  } catch (error) {
    console.error("Error fetching events summary:", error);
    return NextResponse.json(
      { error: "Failed to fetch events summary" },
      { status: 500 }
    );
  }
}

export const GET = withProtectedRoute(handler, {
  permissions: [Permission.MANAGE_SECURITY],
  requireAll: true,
});
