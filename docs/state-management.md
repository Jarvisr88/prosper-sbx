# State Management Guide

## Overview

This application uses a hybrid state management approach combining Redux Toolkit (RTK) for global state, RTK Query for server state, and local React state for component-level state.

## State Categories

### 1. Server State (RTK Query)

Server state is managed using RTK Query, which provides automatic caching, refetching, and real-time updates.

```typescript
// Example API slice
import { baseApi } from "./baseApi";

export const userApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getUsers: builder.query<User[], void>({
      query: () => "users",
      providesTags: ["User"],
    }),
    updateUser: builder.mutation<User, UpdateUserDto>({
      query: (dto) => ({
        url: `users/${dto.id}`,
        method: "PUT",
        body: dto,
      }),
      invalidatesTags: ["User"],
    }),
  }),
});

// Usage in components
function UserList() {
  const { data: users, isLoading } = userApi.useGetUsersQuery();
}
```

### 2. Global State (Redux)

Global application state is managed using Redux Toolkit. This includes:

- Authentication state
- UI state (theme, sidebar, notifications)
- Cross-component shared state

```typescript
// Example slice
import { createSlice, PayloadAction } from "@reduxjs/toolkit";

const uiSlice = createSlice({
  name: "ui",
  initialState: {
    theme: "light",
    sidebarOpen: false,
  },
  reducers: {
    toggleTheme: (state) => {
      state.theme = state.theme === "light" ? "dark" : "light";
    },
    setSidebarOpen: (state, action: PayloadAction<boolean>) => {
      state.sidebarOpen = action.payload;
    },
  },
});

// Usage in components
function Header() {
  const dispatch = useDispatch();
  const theme = useSelector((state: RootState) => state.ui.theme);

  const handleThemeToggle = () => {
    dispatch(uiSlice.actions.toggleTheme());
  };
}
```

### 3. Local State (React useState)

Component-specific state that doesn't need to be shared should use React's useState:

```typescript
function SearchBar() {
  const [query, setQuery] = useState("");
  const [isExpanded, setIsExpanded] = useState(false);

  // Local state is perfect for UI interactions
  const handleFocus = () => setIsExpanded(true);
  const handleBlur = () => setIsExpanded(false);
}
```

## Best Practices

### 1. When to Use Each Type

- **Server State (RTK Query)**:

  - API data that needs caching
  - Data that requires real-time updates
  - Shared data across multiple components

- **Global State (Redux)**:

  - Authentication state
  - Theme/UI preferences
  - Feature flags
  - Global notifications
  - Shared business logic state

- **Local State (useState)**:
  - Form input values
  - Toggle states (expanded/collapsed)
  - Component-specific UI state
  - Temporary data that doesn't affect other components

### 2. Data Flow

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Server State  │     │   Global State  │     │   Local State   │
│   (RTK Query)   │     │    (Redux)      │     │   (useState)    │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                        │
         ▼                       ▼                        ▼
┌─────────────────────────────────────────────────────────────────┐
│                           Components                             │
└─────────────────────────────────────────────────────────────────┘
```

### 3. Type Safety

Always use TypeScript interfaces for state:

```typescript
interface AuthState {
  user: User | null;
  token: string | null;
  isAuthenticated: boolean;
}

interface UiState {
  theme: "light" | "dark";
  sidebarOpen: boolean;
  notifications: Notification[];
}
```

### 4. Performance Considerations

- Use RTK Query's automatic caching to prevent unnecessary API calls
- Implement proper tag invalidation for cache management
- Use selectors to prevent unnecessary re-renders
- Consider using `useMemo` and `useCallback` for expensive computations

## Common Patterns

### 1. Data Fetching

```typescript
// Preferred: RTK Query
const { data, isLoading } = useGetUsersQuery();

// Alternative: Custom Hook
const { data, loading, error } = useApi<User[]>("/api/users");
```

### 2. Form State

```typescript
// Local state for forms
const [formData, setFormData] = useState<FormData>({
  name: "",
  email: "",
});

// Global state for form submission
const [updateUser] = useUpdateUserMutation();
```

### 3. UI State

```typescript
// Global UI state
const theme = useSelector((state: RootState) => state.ui.theme);

// Local UI state
const [isOpen, setIsOpen] = useState(false);
```

## Debugging

1. Use Redux DevTools for global state inspection
2. Use RTK Query's built-in loading/error states
3. Implement proper error boundaries
4. Use TypeScript for type safety

## Examples

### Complete Component Example

```typescript
function UserProfile() {
  // Server state
  const { data: user, isLoading } = useGetUserQuery(userId);

  // Global state
  const theme = useSelector((state: RootState) => state.ui.theme);

  // Local state
  const [isEditing, setIsEditing] = useState(false);

  if (isLoading) return <Spinner />;

  return (
    <Card theme={theme}>
      <UserInfo user={user} />
      <Button onClick={() => setIsEditing(!isEditing)}>
        {isEditing ? 'Cancel' : 'Edit'}
      </Button>
    </Card>
  );
}
```

## Migration Guide

When migrating existing components:

1. Move API calls to RTK Query endpoints
2. Move shared state to Redux slices
3. Keep component-specific state as local state
4. Update types and interfaces accordingly
