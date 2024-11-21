import { createSlice, PayloadAction } from '@reduxjs/toolkit'

interface UiState {
  sidebarOpen: boolean
  theme: 'light' | 'dark'
  notifications: Array<{
    id: string
    type: 'success' | 'error' | 'warning' | 'info'
    message: string
  }>
  loading: {
    [key: string]: boolean
  }
}

const initialState: UiState = {
  sidebarOpen: true,
  theme: 'light',
  notifications: [],
  loading: {}
}

const uiSlice = createSlice({
  name: 'ui',
  initialState,
  reducers: {
    toggleSidebar: (state) => {
      state.sidebarOpen = !state.sidebarOpen
    },
    setTheme: (state, action: PayloadAction<'light' | 'dark'>) => {
      state.theme = action.payload
    },
    addNotification: (
      state,
      action: PayloadAction<{
        type: 'success' | 'error' | 'warning' | 'info'
        message: string
      }>
    ) => {
      state.notifications.push({
        id: Date.now().toString(),
        ...action.payload
      })
    },
    removeNotification: (state, action: PayloadAction<string>) => {
      state.notifications = state.notifications.filter(
        (notification) => notification.id !== action.payload
      )
    },
    setLoading: (
      state,
      action: PayloadAction<{ key: string; value: boolean }>
    ) => {
      state.loading[action.payload.key] = action.payload.value
    }
  }
})

export const {
  toggleSidebar,
  setTheme,
  addNotification,
  removeNotification,
  setLoading
} = uiSlice.actions
export default uiSlice.reducer 