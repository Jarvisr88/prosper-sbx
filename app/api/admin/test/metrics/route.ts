import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";

interface MetricRecord {
  metric_name: string;
  metric_value: number | string;
  metric_type: string;
  collection_time: Date;
  dimensions: Record<string, unknown>;
}

// Helper function to handle partitioned table queries
async function queryPartitionedMetrics({
  startDate,
  endDate,
  metricType,
  limit = 10,
}: {
  startDate?: Date;
  endDate?: Date;
  metricType?: string;
  limit?: number;
}): Promise<MetricRecord[]> {
  // Use raw query for better control over partitioned table
  const result = await prisma.$queryRaw<MetricRecord[]>`
    SELECT 
      metric_name,
      metric_value,
      metric_type,
      collection_time,
      dimensions
    FROM system_metrics_history
    WHERE 
      (${startDate}::timestamp IS NULL OR collection_time >= ${startDate}) AND
      (${endDate}::timestamp IS NULL OR collection_time <= ${endDate}) AND
      (${metricType}::text IS NULL OR metric_type = ${metricType})
    ORDER BY collection_time DESC
    LIMIT ${limit}
  `;

  return result;
}

export async function GET(req: NextRequest) {
  try {
    const { searchParams } = new URL(req.url);
    const type = searchParams.get("type");
    const period = searchParams.get("period") || "24h";

    // Calculate date range based on period
    const endDate = new Date();
    const startDate = new Date(endDate);
    if (period === "7d") {
      startDate.setDate(startDate.getDate() - 7);
    } else if (period === "24h") {
      startDate.setHours(startDate.getHours() - 24);
    } else {
      startDate.setHours(startDate.getHours() - 1);
    }

    const metrics = await queryPartitionedMetrics({
      startDate,
      endDate,
      metricType: type || undefined,
      limit: 50,
    });

    // Calculate aggregates
    const aggregates = metrics.reduce(
      (acc, curr) => {
        const key = curr.metric_name;
        const value = Number(curr.metric_value);

        if (!acc[key]) {
          acc[key] = {
            min: value,
            max: value,
            avg: value,
            count: 1,
          };
        } else {
          acc[key].min = Math.min(acc[key].min, value);
          acc[key].max = Math.max(acc[key].max, value);
          acc[key].avg =
            (acc[key].avg * acc[key].count + value) / (acc[key].count + 1);
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
      success: true,
      data: {
        metrics,
        aggregates,
        period,
        timeRange: {
          start: startDate,
          end: endDate,
        },
      },
    });
  } catch (error) {
    console.error("Metrics history test error:", error);
    return NextResponse.json(
      { error: "Failed to fetch metrics history" },
      { status: 500 }
    );
  }
}

interface MetricInput {
  name: string;
  value: number | string;
  type: string;
  dimensions?: Record<string, unknown>;
}

export async function POST(req: NextRequest) {
  try {
    const data = (await req.json()) as MetricInput;

    // Use raw query to insert into partitioned table
    const result = await prisma.$executeRaw`
      INSERT INTO system_metrics_history (
        metric_name,
        metric_value,
        metric_type,
        dimensions,
        collection_time
      ) VALUES (
        ${data.name},
        ${data.value},
        ${data.type},
        ${data.dimensions || {}},
        ${new Date()}
      )
    `;

    return NextResponse.json({
      success: true,
      data: {
        inserted: result === 1,
        timestamp: new Date(),
      },
    });
  } catch (error) {
    console.error("Metric recording error:", error);
    return NextResponse.json(
      { error: "Failed to record metric" },
      { status: 500 }
    );
  }
}
