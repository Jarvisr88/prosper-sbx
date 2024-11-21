import { render, screen, fireEvent } from '@testing-library/react'
import { signIn } from 'next-auth/react'
import { useSearchParams } from 'next/navigation'
import SignInPage from '@/client/components/auth/SignInPage'

// Mock the modules
jest.mock('next-auth/react')
jest.mock('next/navigation')

describe('SignInPage', () => {
  const mockSignIn = signIn as jest.Mock
  const mockUseSearchParams = useSearchParams as jest.Mock

  beforeEach(() => {
    mockSignIn.mockClear()
    mockUseSearchParams.mockReturnValue({
      get: jest.fn().mockReturnValue(null)
    })
  })

  it('renders sign in page correctly', () => {
    render(<SignInPage />)
    expect(screen.getByText('Sign in to Prosper')).toBeInTheDocument()
    expect(screen.getByText('Sign in with Google')).toBeInTheDocument()
  })

  it('handles Google sign in click', () => {
    render(<SignInPage />)
    fireEvent.click(screen.getByText('Sign in with Google'))
    expect(mockSignIn).toHaveBeenCalledWith('google', { callbackUrl: '/' })
  })

  it('displays error message when error param is present', () => {
    mockUseSearchParams.mockReturnValue({
      get: jest.fn((param) => param === 'error' ? 'Callback' : null)
    })

    render(<SignInPage />)
    expect(screen.getByText('Error signing in')).toBeInTheDocument()
  })

  it('uses custom callback URL when provided', () => {
    const callbackUrl = '/dashboard'
    mockUseSearchParams.mockReturnValue({
      get: jest.fn((param) => param === 'callbackUrl' ? callbackUrl : null)
    })

    render(<SignInPage />)
    fireEvent.click(screen.getByText('Sign in with Google'))
    expect(mockSignIn).toHaveBeenCalledWith('google', { callbackUrl })
  })
}) 