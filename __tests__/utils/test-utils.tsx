import React from 'react'
import { render as rtlRender } from '@testing-library/react'
import { Provider } from 'react-redux'
import { configureStore, type Store, combineReducers } from '@reduxjs/toolkit'
import { SessionProvider } from 'next-auth/react'
import type { Session } from 'next-auth'
import type { RenderOptions } from '@testing-library/react'
import { baseApi } from '@/store/api/baseApi'
import authReducer from '@/store/slices/authSlice'
import uiReducer from '@/store/slices/uiSlice'
import type { RootState } from '@/store/types'

interface ExtendedRenderOptions extends Omit<RenderOptions, 'queries'> {
  preloadedState?: Partial<RootState>
  store?: Store
  session?: Session
}

function render(
  ui: React.ReactElement,
  {
    preloadedState,
    store = configureStore({
      reducer: combineReducers({
        api: baseApi.reducer,
        auth: authReducer,
        ui: uiReducer
      }),
      middleware: (getDefaultMiddleware) =>
        getDefaultMiddleware({
          serializableCheck: false
        }).concat(baseApi.middleware),
      preloadedState
    }),
    session = {
      user: { 
        name: 'Test User', 
        email: 'test@example.com', 
        role: 'user',
        id: '1'
      },
      expires: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString() // 24 hours from now
    },
    ...renderOptions
  }: ExtendedRenderOptions = {}
) {
  function Wrapper({ children }: { children: React.ReactNode }) {
    return (
      <SessionProvider session={session}>
        <Provider store={store}>{children}</Provider>
      </SessionProvider>
    )
  }
  return rtlRender(ui, { wrapper: Wrapper, ...renderOptions })
}

export * from '@testing-library/react'
export { render } 