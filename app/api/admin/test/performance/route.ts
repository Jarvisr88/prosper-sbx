import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { Validators } from "@/middleware/validation/schemaValidation";

export async function GET() {
  try {
    const scores = await prisma.performance_scores.findMany({
      take: 5,
      orderBy: {
        created_at: "desc",
      },
      select: {
        initial_self_score: true,
        self_score: true,
        manager_score: true,
        challenge_score: true,
        concurrent_score: true,
        created_at: true,
      },
    });

    return NextResponse.json({
      success: true,
      data: scores,
    });
  } catch (error) {
    console.error("Performance scores test error:", error);
    return NextResponse.json(
      { error: "Failed to fetch performance scores" },
      { status: 500 }
    );
  }
}

export async function POST(req: NextRequest) {
  return Validators.performanceScore(req, async () => {
    try {
      const data = await req.json();
      const score = await prisma.performance_scores.create({
        data: {
          ...data,
          created_at: new Date(),
        },
      });

      return NextResponse.json({
        success: true,
        data: score,
      });
    } catch (error) {
      console.error("Performance score creation error:", error);
      return NextResponse.json(
        { error: "Failed to create performance score" },
        { status: 500 }
      );
    }
  });
}
