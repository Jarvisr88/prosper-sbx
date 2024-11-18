import { headers } from "next/headers"

export type ApiResponse<T> = {
  data?: T
  error?: string
  status: number
}

export async function fetchApi<T>(
  endpoint: string, 
  options: RequestInit = {}
): Promise<ApiResponse<T>> {
  try {
    const headersList = await headers()
    const defaultOptions: RequestInit = {
      headers: {
        "Content-Type": "application/json",
        "Authorization": headersList.get("Authorization") || "",
      },
    }

    const response = await fetch(
      `${process.env.NEXT_PUBLIC_API_URL}${endpoint}`,
      { ...defaultOptions, ...options }
    )
    const data = await response.json()

    return {
      data: data as T,
      status: response.status
    }
  } catch (error) {
    return {
      error: error instanceof Error ? error.message : "An error occurred",
      status: 500
    }
  }
} 