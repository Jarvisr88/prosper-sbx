import { NextRequest, NextResponse } from "next/server";
import { withProtectedRoute } from "@/middleware/auth/withProtectedRoute";
import { Permission } from "@/types/auth/permissions";
import { prisma } from "@/lib/prisma";

async function handler(req: NextRequest) {
  if (req.method === "GET") {
    const { searchParams } = new URL(req.url);
    const metric_type = searchParams.get("type");
    const period = searchParams.get("period") || "24h";

    return await getMetrics(metric_type, period);
  }

  if (req.method === "POST") {
    return await recordMetric(req);
  }

  return NextResponse.json({ error: "Method not allowed" }, { status: 405 });
}

async function getMetrics(metric_type: string | null, period: string) {
  try {
    const hours = period === "7d" ? 168 : period === "1d" ? 24 : 1;

    const metrics = await prisma.system_metrics_history.findMany({
      where: {
        ...(metric_type && { metric_type }),
        collection_time: {
          gte: new Date(Date.now() - hours * 60 * 60 * 1000),
        },
      },
      orderBy: {
        collection_time: "desc",
      },
      select: {
        metric_name: true,
        metric_value: true,
        metric_type: true,
        collection_time: true,
        dimensions: true,
      },
    });

    // Calculate aggregates
    const aggregates = metrics.reduce(
      (acc, curr) => {
        const key = curr.metric_name;
        if (!acc[key]) {
          acc[key] = {
            min: Number(curr.metric_value),
            max: Number(curr.metric_value),
            avg: Number(curr.metric_value),
            count: 1,
          };
        } else {
          acc[key].min = Math.min(acc[key].min, Number(curr.metric_value));
          acc[key].max = Math.max(acc[key].max, Number(curr.metric_value));
          acc[key].avg =
            (acc[key].avg * acc[key].count + Number(curr.metric_value)) /
            (acc[key].count + 1);
          acc[key].count++;
        }
        return acc;
      },
      {} as Record<
        string,
        { min: number; max: number; avg: number; count: number }
      >
    );

    return NextResponse.json({
      metrics,
      aggregates,
      period,
      timestamp: new Date(),
    });
  } catch (error) {
    console.error("Metrics retrieval error:", error);
    return NextResponse.json(
      { error: "Failed to retrieve metrics" },
      { status: 500 }
    );
  }
}

async function recordMetric(req: NextRequest) {
  try {
    const data = await req.json();
    const metric = await prisma.system_metrics_history.create({
      data: {
        metric_name: data.name,
        metric_value: data.value,
        metric_type: data.type,
        dimensions: data.dimensions || {},
        collection_time: new Date(),
      },
    });

    return NextResponse.json({ metric });
  } catch (error) {
    console.error("Metric recording error:", error);
    return NextResponse.json(
      { error: "Failed to record metric" },
      { status: 500 }
    );
  }
}

export const GET = withProtectedRoute(handler, {
  permissions: [Permission.MANAGE_SETTINGS],
  requireAll: true,
});

export const POST = withProtectedRoute(handler, {
  permissions: [Permission.MANAGE_SETTINGS],
  requireAll: true,
});
