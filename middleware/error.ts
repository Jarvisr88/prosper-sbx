import { NextResponse } from "next/server";

export function handleError(error: unknown) {
  console.error("API Error:", error);

  if (error instanceof Error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json(
    { error: "An unexpected error occurred" },
    { status: 500 }
  );
}
