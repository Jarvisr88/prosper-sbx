# State Management Quick Start

## 🚀 Getting Started

### 1. Server State (API Data)

```typescript
// 1. Import the hook
import { useGetUsersQuery } from '@/store/api/userApi';

// 2. Use in component
function UserList() {
  const { data, isLoading, error } = useGetUsersQuery();

  if (isLoading) return <Spinner />;
  if (error) return <Error message={error.message} />;

  return <List items={data} />;
}
```

### 2. Global State

```typescript
// 1. Import hooks
import { useSelector, useDispatch } from 'react-redux';
import { setTheme } from '@/store/slices/uiSlice';

// 2. Use in component
function ThemeToggle() {
  const dispatch = useDispatch();
  const theme = useSelector((state) => state.ui.theme);

  return (
    <button onClick={() => dispatch(setTheme(theme === 'light' ? 'dark' : 'light'))}>
      Toggle Theme
    </button>
  );
}
```

### 3. Local State

```typescript
// Just use useState for component-specific state
function Counter() {
  const [count, setCount] = useState(0);

  return (
    <button onClick={() => setCount(count + 1)}>
      Count: {count}
    </button>
  );
}
```

## 🎯 Quick Decision Guide

Use this decision tree to choose the right state management approach:

1. Is it API data?

   - Yes → Use RTK Query
   - No → Continue to 2

2. Does other components need this data?

   - Yes → Use Redux
   - No → Continue to 3

3. Is it just UI state for this component?
   - Yes → Use useState
   - No → Use Redux

## 🔍 Common Use Cases

### API Data

```typescript
// ✅ DO: Use RTK Query
const { data } = useGetUsersQuery();

// ❌ DON'T: Use local state
const [users, setUsers] = useState([]);
useEffect(() => {
  fetch("/api/users").then(/*...*/);
}, []);
```

### Shared State

```typescript
// ✅ DO: Use Redux
const theme = useSelector((state) => state.ui.theme);

// ❌ DON'T: Prop drill
function App({ theme }) {
  return <Header theme={theme}>
    <Nav theme={theme}>
      <Menu theme={theme} />
    </Nav>
  </Header>;
}
```

### Component State

```typescript
// ✅ DO: Use useState for local UI state
const [isOpen, setIsOpen] = useState(false);

// ❌ DON'T: Use Redux for component-specific state
const isOpen = useSelector((state) => state.ui.menuStates[componentId]);
```

## 🐛 Debugging Tips

1. Install Redux DevTools browser extension
2. Use the Network tab for RTK Query requests
3. Add console.logs in selectors for debugging
4. Check React DevTools for component state

## 🆘 Common Issues

### 1. Infinite Re-renders

```typescript
// ❌ Problem
useEffect(() => {
  dispatch(someAction());
}, [someValue]);

// ✅ Solution
useEffect(() => {
  if (someValue) {
    dispatch(someAction());
  }
}, [someValue]);
```

### 2. Stale Data

```typescript
// ❌ Problem
const { data } = useGetUsersQuery();
useEffect(() => {
  // Manual refetch
  refetch();
}, []);

// ✅ Solution
const { data } = useGetUsersQuery(undefined, {
  pollingInterval: 60000, // Auto-refresh every minute
});
```

## 📚 Resources

- [Redux Toolkit Docs](https://redux-toolkit.js.org/)
- [RTK Query Overview](https://redux-toolkit.js.org/rtk-query/overview)
- [React useState Guide](https://react.dev/reference/react/useState)
- Full documentation: See `state-management.md`
