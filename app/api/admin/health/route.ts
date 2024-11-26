import { NextRequest, NextResponse } from "next/server";
import { withProtectedRoute } from "@/middleware/auth/withProtectedRoute";
import { Permission } from "@/types/auth/permissions";
import { prisma } from "@/lib/prisma";

async function handler(req: NextRequest) {
  if (req.method === "GET") {
    const { searchParams } = new URL(req.url);
    const metric = searchParams.get("metric");

    switch (metric) {
      case "system":
        return await getSystemMetrics();
      case "performance":
        return await getPerformanceMetrics();
      case "monitoring":
        return await getMonitoringLogs();
      default:
        return NextResponse.json(
          { error: "Invalid metric type" },
          { status: 400 }
        );
    }
  }

  return NextResponse.json({ error: "Method not allowed" }, { status: 405 });
}

async function getSystemMetrics() {
  try {
    const [activeUsers, activeSessions, securityEvents, recentWorkflows] =
      await Promise.all([
        prisma.users.count({ where: { is_active: true } }),
        prisma.user_sessions.count({
          where: {
            is_valid: true,
            expires_at: { gt: new Date() },
          },
        }),
        prisma.security_events.count({
          where: {
            event_time: {
              gte: new Date(Date.now() - 24 * 60 * 60 * 1000), // Last 24 hours
            },
          },
        }),
        prisma.workflow_executions.count({
          where: {
            started_at: {
              gte: new Date(Date.now() - 24 * 60 * 60 * 1000),
            },
          },
        }),
      ]);

    return NextResponse.json({
      metrics: {
        activeUsers,
        activeSessions,
        securityEvents,
        recentWorkflows,
      },
      timestamp: new Date(),
    });
  } catch (error) {
    console.error("System metrics error:", error);
    return NextResponse.json(
      { error: "Failed to retrieve system metrics" },
      { status: 500 }
    );
  }
}

async function getPerformanceMetrics() {
  try {
    const monitoringData = await prisma.security_monitoring_log.findFirst({
      orderBy: { execution_time: "desc" },
    });

    const performanceAlerts = await prisma.system_metrics_history.count({
      where: {
        collection_time: {
          gte: new Date(Date.now() - 24 * 60 * 60 * 1000),
        },
        metric_type: "ALERT",
      },
    });

    return NextResponse.json({
      monitoring: monitoringData,
      alerts: performanceAlerts,
      timestamp: new Date(),
    });
  } catch (error) {
    console.error("Performance metrics error:", error);
    return NextResponse.json(
      { error: "Failed to retrieve performance metrics" },
      { status: 500 }
    );
  }
}

async function getMonitoringLogs() {
  try {
    const logs = await prisma.security_monitoring_log.findMany({
      orderBy: { execution_time: "desc" },
      take: 100,
    });

    return NextResponse.json({
      logs,
      timestamp: new Date(),
    });
  } catch (error) {
    console.error("Monitoring logs error:", error);
    return NextResponse.json(
      { error: "Failed to retrieve monitoring logs" },
      { status: 500 }
    );
  }
}

export const GET = withProtectedRoute(handler, {
  permissions: [Permission.MANAGE_SETTINGS],
  requireAll: true,
});
