import { createSwaggerSpec } from "next-swagger-doc";
import { NextResponse } from "next/server";

const apiConfig = {
  openapi: "3.0.0",
  info: {
    title: "Prosper API Documentation",
    version: "1.0",
    description: "Documentation for Prosper API endpoints",
  },
  servers: [
    {
      url: process.env.NEXTAUTH_URL || "http://localhost:3003",
      description: "Server URL",
    },
  ],
  security: [
    {
      bearerAuth: [],
    },
  ],
  components: {
    securitySchemes: {
      bearerAuth: {
        type: "http",
        scheme: "bearer",
        bearerFormat: "JWT",
      },
    },
  },
};

export async function GET() {
  const spec = createSwaggerSpec({
    apiFolder: "app/api",
    definition: apiConfig,
  });

  return NextResponse.json(spec);
}
