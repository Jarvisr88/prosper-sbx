# Development Team Hand-off Guide

## Project Overview

This is a Next.js TypeScript application with a focus on enterprise-grade state management, database integration, and robust type safety.

### Key Technologies

- **Framework**: Next.js 15.0.3
- **Language**: TypeScript 5.6.3
- **Database**: PostgreSQL (via Prisma 5.22.0)
- **State Management**: Redux Toolkit + RTK Query
- **UI Components**: Custom components with Tailwind CSS
- **Authentication**: NextAuth.js
- **API Documentation**: Swagger/OpenAPI
- **Testing**: Jest + Testing Library

## Project Structure

```
prosper-sbx/
├── app/                    # Next.js 13+ App Router
│   ├── api/               # API Routes
│   ├── admin/             # Admin Pages
│   └── users/             # User Pages
├── components/            # React Components
│   ├── ui/               # UI Components
│   └── providers/        # Context Providers
├── lib/                   # Utility Functions
├── middleware/            # Request Middleware
│   └── validation/       # Schema Validation
├── prisma/               # Database Schema
├── store/                # Redux Store
│   ├── api/             # RTK Query APIs
│   └── slices/          # Redux Slices
├── types/                # TypeScript Types
└── docs/                # Documentation
```

## Getting Started

1. **Environment Setup**

   ```bash
   # Install dependencies
   npm install

   # Set up environment variables
   cp .env.example .env.local

   # Generate Prisma client
   npx prisma generate

   # Start development server
   npm run dev
   ```

2. **Database Connection**

   - Database URL is configured in `.env.local`
   - Prisma schema is in `prisma/schema.prisma`
   - Run `npx prisma db pull` to sync schema changes

3. **Authentication**
   - NextAuth.js configuration in `pages/api/auth/[...nextauth].ts`
   - Protected routes use `withProtectedRoute` middleware
   - JWT tokens handled automatically

## Key Features and Implementation

### 1. State Management

Refer to `docs/state-management.md` for detailed documentation. Key points:

- Server State: RTK Query
- Global State: Redux Toolkit
- Local State: React useState
- Session State: NextAuth.js

### 2. Database Integration

```typescript
// Example Prisma query with validation
async function getUser(id: number) {
  try {
    const user = await prisma.users.findUnique({
      where: { user_id: id },
      select: {
        user_id: true,
        username: true,
        email: true,
        role: true,
      },
    });
    return user;
  } catch (error) {
    console.error("Database error:", error);
    throw new Error("Failed to fetch user");
  }
}
```

### 3. API Structure

- RESTful endpoints in `app/api/`
- Protected routes use `withProtectedRoute` middleware
- Validation using Zod schemas
- Error handling middleware

### 4. Type Safety

```typescript
// Example type definitions
interface User {
  id: number;
  username: string;
  email: string;
  role: UserRole;
}

enum UserRole {
  ADMIN = "ADMIN",
  USER = "USER",
  GUEST = "GUEST",
}
```

## Development Workflow

### 1. Code Style and Linting

- ESLint configuration in `.eslintrc.js`
- Prettier configuration in `.prettierrc`
- Pre-commit hooks using lint-staged

### 2. Branch Strategy

- main: Production branch
- develop: Development branch
- feature/\*: Feature branches
- bugfix/\*: Bug fix branches

### 3. Testing

```typescript
// Example test
describe('UserProfile', () => {
  it('renders user information', () => {
    render(<UserProfile user={mockUser} />);
    expect(screen.getByText(mockUser.username)).toBeInTheDocument();
  });
});
```

### 4. Deployment

- Production: Vercel platform
- Environment variables in Vercel dashboard
- Automatic deployments on main branch

## Known Issues and Workarounds

1. **Prisma Limitations**

   - Partitioned tables not fully supported
   - Using raw SQL queries for system_metrics_history
   - Check constraints implemented in validation layer

2. **Type Generation**

   - Run `npm run generate-types` after schema changes
   - Some types require manual augmentation

3. **State Management Edge Cases**
   - See `docs/state-management.md` for details
   - Use optimistic updates carefully

## Performance Considerations

1. **Database Queries**

   ```typescript
   // ✅ DO: Use select
   const users = await prisma.users.findMany({
     select: {
       id: true,
       username: true,
     },
   });

   // ❌ DON'T: Fetch all fields
   const users = await prisma.users.findMany();
   ```

2. **API Routes**

   - Use proper caching headers
   - Implement rate limiting
   - Validate request bodies

3. **Frontend Performance**
   - Implement proper code splitting
   - Use React.memo for expensive components
   - Optimize images using Next.js Image component

## Security Measures

1. **Authentication**

   - JWT tokens with proper expiration
   - Role-based access control
   - Protected API routes

2. **Data Validation**

   - Input sanitization
   - Schema validation
   - SQL injection prevention

3. **API Security**
   - Rate limiting
   - CORS configuration
   - Content Security Policy

## Monitoring and Debugging

1. **Error Tracking**

   - Console logging in development
   - Error boundaries for React components
   - API error handling

2. **Performance Monitoring**

   - React DevTools
   - Redux DevTools
   - Network tab monitoring

3. **Database Monitoring**
   - Prisma Studio for database inspection
   - Query performance monitoring
   - Connection pool management

## Next Steps and Roadmap

1. **Immediate Tasks**

   - Complete user management features
   - Implement real-time notifications
   - Add comprehensive test coverage

2. **Future Improvements**

   - GraphQL integration
   - WebSocket support
   - Enhanced caching strategy

3. **Technical Debt**
   - Refactor validation logic
   - Optimize database queries
   - Update dependencies

## Support and Resources

1. **Documentation**

   - Project: `/docs`
   - API: Swagger UI at `/api-docs`
   - State Management: `docs/state-management.md`

2. **Key Contacts**

   - Technical Lead: [Contact Info]
   - Database Admin: [Contact Info]
   - DevOps: [Contact Info]

3. **Useful Links**
   - Internal Wiki
   - Design System
   - API Documentation

## Common Tasks

### Adding a New Feature

1. Create feature branch
2. Update Prisma schema if needed
3. Generate types
4. Create API endpoints
5. Implement RTK Query endpoints
6. Create UI components
7. Add tests
8. Update documentation

### Debugging Production Issues

1. Check error logs
2. Verify database connectivity
3. Check Redis cache
4. Inspect API responses
5. Review state management
6. Check authentication status

## Conclusion

This project follows best practices for enterprise React applications with a focus on:

- Type safety
- State management
- Performance
- Security
- Maintainability

For any questions or issues, refer to the documentation or contact the technical lead.
