// Directory: C:\prosper-sbx\server\services\base.ts
// Create directory: New-Item -Path "C:\prosper-sbx\server\services" -ItemType Directory -Force

export type ServiceResponse<T> = {
  data?: T
  error?: string
  status: number
}

export class BaseService {
  protected async fetchData<T>(
    url: string,
    options: RequestInit = {}
  ): Promise<ServiceResponse<T>> {
    try {
      const response = await fetch(url, {
        ...options,
        headers: {
          'Content-Type': 'application/json',
          ...options.headers,
        }
      })

      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }

      const data = await response.json()
      return {
        data: data as T,
        status: response.status
      }
    } catch (error) {
      return this.handleError(error)
    }
  }

  protected handleError(error: unknown): ServiceResponse<never> {
    console.error('Service error:', error)
    return {
      error: error instanceof Error ? error.message : 'An error occurred',
      status: 500
    }
  }
}