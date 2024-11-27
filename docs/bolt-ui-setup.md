# Bolt UI (shadcn/ui) Setup Guide

## Initial Setup

1. **Install Dependencies**

   ```bash
   npm install tailwindcss-animate class-variance-authority clsx tailwind-merge lucide-react @radix-ui/react-slot
   ```

2. **Update Tailwind Configuration**

   ```typescript
   // tailwind.config.ts
   import { fontFamily } from "tailwindcss/defaultTheme";
   import type { Config } from "tailwindcss";
   import animate from "tailwindcss-animate";

   export default {
     darkMode: ["class"],
     content: [
       "./pages/**/*.{ts,tsx}",
       "./components/**/*.{ts,tsx}",
       "./app/**/*.{ts,tsx}",
       "./src/**/*.{ts,tsx}",
     ],
     theme: {
       container: {
         center: true,
         padding: "2rem",
         screens: {
           "2xl": "1400px",
         },
       },
       extend: {
         // ... rest of your theme config
       },
     },
     plugins: [animate],
   } satisfies Config;
   ```

3. **Add CSS Variables**
   Your `globals.css` is already set up correctly with the necessary variables.

## Adding Components

1. **Initialize Components Directory**

   ```bash
   mkdir -p components/ui
   ```

2. **Add Registry for Server Components**

   ```typescript
   // components/ui/registry.tsx
   'use client'

   import React from 'react'
   import { useServerInsertedHTML } from 'next/navigation'

   export function Registry({ children }: { children: React.ReactNode }) {
     useServerInsertedHTML(() => {
       return (
         <>
           <style>{`:root { --font-sans: Inter; }`}</style>
         </>
       )
     })

     return <>{children}</>
   }
   ```

3. **Add Utils**

   ```typescript
   // lib/utils.ts
   import { type ClassValue, clsx } from "clsx";
   import { twMerge } from "tailwind-merge";

   export function cn(...inputs: ClassValue[]) {
     return twMerge(clsx(inputs));
   }
   ```

## Using Components

### Basic Components

1. **Button Example**

   ```typescript
   import { Button } from "@/components/ui/button"

   export default function Page() {
     return (
       <Button variant="outline">
         Click me
       </Button>
     )
   }
   ```

2. **Card Example**

   ```typescript
   import {
     Card,
     CardContent,
     CardDescription,
     CardFooter,
     CardHeader,
     CardTitle,
   } from "@/components/ui/card"

   export default function Page() {
     return (
       <Card>
         <CardHeader>
           <CardTitle>Card Title</CardTitle>
           <CardDescription>Card Description</CardDescription>
         </CardHeader>
         <CardContent>
           <p>Card Content</p>
         </CardContent>
         <CardFooter>
           <p>Card Footer</p>
         </CardFooter>
       </Card>
     )
   }
   ```

## Adding New Components

1. **Using CLI (Recommended)**

   ```bash
   npx shadcn@latest add [component-name]

   # Examples:
   npx shadcn@latest add button
   npx shadcn@latest add card
   npx shadcn@latest add dialog
   ```

2. **Manual Addition**
   - Visit [shadcn/ui website](https://ui.shadcn.com)
   - Copy component code
   - Create new file in `components/ui/`
   - Paste and modify as needed

## Styling Components

### 1. Using Variants

```typescript
<Button
  variant="outline"    // default | destructive | outline | secondary | ghost | link
  size="default"      // default | sm | lg | icon
>
  Click me
</Button>
```

### 2. Custom Styling

```typescript
<Button className="bg-custom-color hover:bg-custom-hover">
  Custom Button
</Button>
```

### 3. Dark Mode

```typescript
// Add to root layout
<html className="dark">
  {/* ... */}
</html>
```

## Best Practices

1. **Component Organization**

   ```
   components/
   ├── ui/              # Base components from shadcn/ui
   └── custom/          # Your custom components
   ```

2. **Reusable Patterns**

   ```typescript
   // components/custom/data-card.tsx
   import { Card, CardHeader, CardContent } from "@/components/ui/card"

   export function DataCard({ title, children }) {
     return (
       <Card>
         <CardHeader>{title}</CardHeader>
         <CardContent>{children}</CardContent>
       </Card>
     )
   }
   ```

3. **Theme Consistency**
   - Use CSS variables defined in `globals.css`
   - Extend theme in `tailwind.config.ts`
   - Create component presets for common patterns

## Common Components to Add

1. **Basic UI**

   ```bash
   npx shadcn@latest add button
   npx shadcn@latest add card
   npx shadcn@latest add input
   ```

2. **Forms**

   ```bash
   npx shadcn@latest add form
   npx shadcn@latest add select
   npx shadcn@latest add checkbox
   ```

3. **Layout**

   ```bash
   npx shadcn@latest add sheet
   npx shadcn@latest add tabs
   npx shadcn@latest add separator
   ```

4. **Feedback**
   ```bash
   npx shadcn@latest add toast
   npx shadcn@latest add alert
   npx shadcn@latest add progress
   ```

## Troubleshooting

1. **Style Conflicts**

   - Use `cn()` utility for class merging
   - Check Tailwind class specificity
   - Verify CSS variable definitions

2. **Component Issues**

   - Check dependencies versions
   - Verify component imports
   - Check Registry setup

3. **Dark Mode Issues**
   - Verify class on html/body
   - Check CSS variable definitions
   - Use proper color variables
