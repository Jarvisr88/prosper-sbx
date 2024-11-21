import { NextRequest } from 'next/server'
import { RequestMethod } from 'node-mocks-http'

interface MockRequestOptions {
  method?: RequestMethod
  body?: Record<string, unknown>
  headers?: Record<string, string>
}

export function createMockNextRequest(options: MockRequestOptions) {
  // Create a minimal NextRequest implementation
  const nextRequest = new NextRequest(new Request('http://localhost'), {
    method: options.method || 'GET',
    headers: options.headers ? new Headers(options.headers) : undefined
  })

  // Add the body to the request
  if (options.body) {
    Object.defineProperty(nextRequest, 'json', {
      value: async () => options.body
    })
  }

  return nextRequest
} 