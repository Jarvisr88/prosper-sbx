import '@testing-library/jest-dom'
import { expect } from '@jest/globals'

declare global {
  namespace jest {
    interface Matchers<R> {
      toBeInTheDocument(): R
    }
  }
}

jest.mock('next-auth/react')
jest.mock('next/navigation') 