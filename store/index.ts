import { configureStore } from '@reduxjs/toolkit'
import { setupListeners } from '@reduxjs/toolkit/query'
import { baseApi } from './api/baseApi'
import authReducer from './slices/authSlice'
import uiReducer from './slices/uiSlice'
import type { RootState } from './types'

export const store = configureStore({
  reducer: {
    [baseApi.reducerPath]: baseApi.reducer,
    auth: authReducer,
    ui: uiReducer
  },
  middleware: (getDefaultMiddleware) =>
    getDefaultMiddleware().concat(baseApi.middleware),
  devTools: process.env.NODE_ENV !== 'production'
})

setupListeners(store.dispatch)

export type AppDispatch = typeof store.dispatch
export { type RootState } 