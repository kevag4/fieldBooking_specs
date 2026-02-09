---
inclusion: manual
---

# React 19 Admin Web Application Architecture Context

> When designing or implementing the React admin web application, follow the patterns and standards in this document. It codifies best practices from bulletproof-react (alan2207), TypeScript Style Guide (mkosir), and modern React 19 patterns from the official documentation and community standards.

## 1. Project Structure (Feature-Sliced Design)

### Recommended Directory Structure

```
src/
├── app/                          # Application layer
│   ├── providers/                # All app providers (React Query, Theme, Auth)
│   ├── routes/                   # Route definitions and guards
│   └── App.tsx                   # Root component
│
├── features/                     # Feature modules (domain-driven)
│   ├── auth/
│   │   ├── api/                  # API calls for this feature
│   │   ├── components/           # Feature-specific components
│   │   ├── hooks/                # Feature-specific hooks
│   │   ├── types/                # Feature types
│   │   └── index.ts              # Public API (barrel export)
│   ├── bookings/
│   ├── courts/
│   ├── users/
│   └── dashboard/
│
├── components/                   # Shared UI components
│   ├── ui/                       # Base UI primitives (Button, Input, Card)
│   ├── layout/                   # Layout components (Sidebar, Header)
│   └── feedback/                 # Feedback components (Toast, Modal, Spinner)
│
├── hooks/                        # Shared custom hooks
├── lib/                          # Third-party library configurations
├── services/                     # API client, external services
├── stores/                       # Global state (Zustand stores)
├── types/                        # Shared TypeScript types
├── utils/                        # Utility functions
└── test/                         # Test utilities and setup
```


### Feature Module Structure

Each feature is self-contained with its own API, components, hooks, and types:

```
features/bookings/
├── api/
│   ├── getBookings.ts
│   ├── createBooking.ts
│   └── index.ts
├── components/
│   ├── BookingList/
│   │   ├── BookingList.tsx
│   │   ├── BookingList.test.tsx
│   │   └── index.ts
│   ├── BookingForm/
│   └── BookingCard/
├── hooks/
│   ├── useBookings.ts
│   └── useCreateBooking.ts
├── types/
│   └── index.ts
└── index.ts                      # Public exports only
```

### Import Rules

| Import Type | Pattern | Example |
|-------------|---------|---------|
| Within feature | Relative `./` | `import { BookingCard } from './components/BookingCard'` |
| Cross-feature | Absolute `@/features/` | `import { useAuth } from '@/features/auth'` |
| Shared components | Absolute `@/components/` | `import { Button } from '@/components/ui'` |
| Utilities | Absolute `@/utils/` | `import { formatDate } from '@/utils/date'` |

## 2. TypeScript Standards

### Type Definitions

```typescript
// ✅ Use type aliases (not interfaces) for consistency
type User = {
  id: string;
  email: string;
  role: UserRole;
  createdAt: Date;
};

type UserRole = 'admin' | 'manager' | 'staff';

// ✅ Use discriminated unions for complex state
type AsyncState<T> =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'success'; data: T }
  | { status: 'error'; error: Error };

// ✅ Use const assertions for constants
const BOOKING_STATUS = ['pending', 'confirmed', 'cancelled'] as const;
type BookingStatus = (typeof BOOKING_STATUS)[number];

// ✅ Use satisfies for type-safe constants
const API_ENDPOINTS = {
  bookings: '/api/v1/bookings',
  users: '/api/v1/users',
  courts: '/api/v1/courts',
} as const satisfies Record<string, string>;
```

### Component Props Typing

```typescript
// ✅ Extend HTML element props when wrapping native elements
type ButtonProps = {
  variant?: 'primary' | 'secondary' | 'danger';
  loading?: boolean;
} & Omit<ComponentPropsWithRef<'button'>, 'className'>;

// ✅ Use discriminated unions for conditional props
type ModalProps =
  | { variant: 'alert'; message: string; onConfirm: () => void }
  | { variant: 'form'; children: ReactNode; onSubmit: () => void };

// ✅ Generic components with proper constraints
type ListProps<T> = {
  items: ReadonlyArray<T>;
  renderItem: (item: T, index: number) => ReactNode;
  keyExtractor: (item: T) => string;
};

function List<T>({ items, renderItem, keyExtractor }: ListProps<T>) {
  return (
    <ul>
      {items.map((item, index) => (
        <li key={keyExtractor(item)}>{renderItem(item, index)}</li>
      ))}
    </ul>
  );
}
```


### Naming Conventions

| Category | Convention | Example |
|----------|------------|---------|
| Components | PascalCase | `BookingCard`, `UserProfile` |
| Hooks | camelCase with `use` prefix | `useBookings`, `useAuth` |
| Types | PascalCase | `BookingStatus`, `UserRole` |
| Props types | `[Component]Props` | `BookingCardProps` |
| Constants | SCREAMING_SNAKE_CASE | `API_BASE_URL`, `MAX_RETRIES` |
| Functions | camelCase | `formatCurrency`, `validateEmail` |
| Event handlers | `handle[Event]` | `handleClick`, `handleSubmit` |
| Callback props | `on[Event]` | `onClick`, `onSubmit` |
| Booleans | `is`, `has`, `should` prefix | `isLoading`, `hasError` |
| Generics | `T` prefix + descriptive | `TData`, `TResponse` |

## 3. React 19 Patterns & Hooks

### New React 19 Hooks

```typescript
// ✅ use() API for reading promises and context conditionally
import { use, Suspense } from 'react';

function UserProfile({ userPromise }: { userPromise: Promise<User> }) {
  const user = use(userPromise); // Suspends until resolved
  return <div>{user.name}</div>;
}

// Usage with Suspense
<Suspense fallback={<Skeleton />}>
  <UserProfile userPromise={fetchUser(userId)} />
</Suspense>

// ✅ useActionState for form handling
import { useActionState } from 'react';

async function createBooking(prevState: FormState, formData: FormData) {
  const result = await api.createBooking(Object.fromEntries(formData));
  return result.success 
    ? { success: true, errors: null }
    : { success: false, errors: result.errors };
}

function BookingForm() {
  const [state, formAction] = useActionState(createBooking, { 
    success: false, 
    errors: null 
  });

  return (
    <form action={formAction}>
      <input name="courtId" required />
      <input name="date" type="date" required />
      <button type="submit">Book</button>
      {state.errors && <ErrorList errors={state.errors} />}
    </form>
  );
}

// ✅ useOptimistic for instant UI feedback
import { useOptimistic } from 'react';

function BookingList({ bookings }: { bookings: Booking[] }) {
  const [optimisticBookings, addOptimistic] = useOptimistic(
    bookings,
    (state, newBooking: Booking) => [...state, { ...newBooking, pending: true }]
  );

  async function handleCreate(formData: FormData) {
    const tempBooking = { id: crypto.randomUUID(), ...Object.fromEntries(formData) };
    addOptimistic(tempBooking);
    await api.createBooking(formData);
  }

  return (
    <ul>
      {optimisticBookings.map(booking => (
        <li key={booking.id} style={{ opacity: booking.pending ? 0.5 : 1 }}>
          {booking.courtName}
        </li>
      ))}
    </ul>
  );
}

// ✅ useFormStatus for submit button state
import { useFormStatus } from 'react-dom';

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <button type="submit" disabled={pending}>
      {pending ? 'Submitting...' : 'Submit'}
    </button>
  );
}
```


### React 19 Simplified APIs

```typescript
// ✅ ref as prop (no more forwardRef)
function Input({ ref, label, ...props }: InputProps) {
  return (
    <div>
      <label>{label}</label>
      <input ref={ref} {...props} />
    </div>
  );
}

// ✅ Simplified Context Provider
<ThemeContext value={theme}>
  <App />
</ThemeContext>

// ✅ Document metadata in components
function BookingPage({ booking }: { booking: Booking }) {
  return (
    <article>
      <title>{booking.courtName} - Admin Dashboard</title>
      <meta name="description" content={`Booking details for ${booking.courtName}`} />
      <h1>{booking.courtName}</h1>
    </article>
  );
}

// ✅ Ref cleanup functions
function ScrollTracker() {
  return (
    <div
      ref={(element) => {
        if (!element) return;
        const handler = () => console.log('scrolled');
        element.addEventListener('scroll', handler);
        return () => element.removeEventListener('scroll', handler);
      }}
    />
  );
}
```

### Custom Hooks Best Practices

```typescript
// ✅ Custom hooks must return objects (not arrays for complex returns)
function useBookings(filters: BookingFilters) {
  const [data, setData] = useState<Booking[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  // ... implementation

  return { data, isLoading, error, refetch }; // Object, not array
}

// ✅ Compose hooks for complex logic
function useAuthenticatedBookings() {
  const { user } = useAuth();
  const { data: bookings, isLoading } = useBookings({ userId: user?.id });
  const { hasPermission } = usePermissions();

  return {
    bookings,
    isLoading,
    canCreate: hasPermission('booking:create'),
    canDelete: hasPermission('booking:delete'),
  };
}

// ✅ Hooks rules - only call at top level
function BookingCard({ bookingId }: { bookingId: string }) {
  // ❌ WRONG: Conditional hook
  // if (bookingId) { const booking = useBooking(bookingId); }

  // ✅ CORRECT: Conditional logic inside hook
  const booking = useBooking(bookingId || null);
  
  if (!booking) return null;
  return <Card>{booking.courtName}</Card>;
}
```

## 4. State Management

### State Management Decision Tree

```
Is it server state (from API)?
├── YES → Use TanStack Query
└── NO → Is it shared across multiple components?
    ├── YES → Is it truly global (auth, theme)?
    │   ├── YES → Use Zustand
    │   └── NO → Lift state up or use Context
    └── NO → Use local useState/useReducer
```


### TanStack Query (Server State)

```typescript
// ✅ Query hook with proper typing
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';

// Query keys factory pattern
const bookingKeys = {
  all: ['bookings'] as const,
  lists: () => [...bookingKeys.all, 'list'] as const,
  list: (filters: BookingFilters) => [...bookingKeys.lists(), filters] as const,
  details: () => [...bookingKeys.all, 'detail'] as const,
  detail: (id: string) => [...bookingKeys.details(), id] as const,
};

// Query hook
function useBookings(filters: BookingFilters) {
  return useQuery({
    queryKey: bookingKeys.list(filters),
    queryFn: () => api.getBookings(filters),
    staleTime: 5 * 60 * 1000, // 5 minutes
  });
}

// Mutation with optimistic updates
function useCreateBooking() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: api.createBooking,
    onMutate: async (newBooking) => {
      await queryClient.cancelQueries({ queryKey: bookingKeys.lists() });
      const previous = queryClient.getQueryData(bookingKeys.lists());
      
      queryClient.setQueryData(bookingKeys.lists(), (old: Booking[]) => [
        ...old,
        { ...newBooking, id: 'temp', pending: true },
      ]);
      
      return { previous };
    },
    onError: (err, newBooking, context) => {
      queryClient.setQueryData(bookingKeys.lists(), context?.previous);
    },
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: bookingKeys.lists() });
    },
  });
}
```

### Zustand (Global Client State)

```typescript
// ✅ Zustand store with TypeScript
import { create } from 'zustand';
import { persist, devtools } from 'zustand/middleware';

type AuthState = {
  user: User | null;
  token: string | null;
  isAuthenticated: boolean;
  login: (credentials: LoginCredentials) => Promise<void>;
  logout: () => void;
};

const useAuthStore = create<AuthState>()(
  devtools(
    persist(
      (set) => ({
        user: null,
        token: null,
        isAuthenticated: false,
        login: async (credentials) => {
          const { user, token } = await api.login(credentials);
          set({ user, token, isAuthenticated: true });
        },
        logout: () => {
          set({ user: null, token: null, isAuthenticated: false });
        },
      }),
      { name: 'auth-storage' }
    )
  )
);

// ✅ Use selectors to prevent unnecessary re-renders
function UserAvatar() {
  const user = useAuthStore((state) => state.user);
  return user ? <Avatar src={user.avatar} /> : null;
}

// ✅ Multiple small stores over one large store
const useUIStore = create<UIState>()((set) => ({
  sidebarOpen: true,
  theme: 'light',
  toggleSidebar: () => set((state) => ({ sidebarOpen: !state.sidebarOpen })),
  setTheme: (theme) => set({ theme }),
}));
```

## 5. Form Handling

### React Hook Form + Zod

```typescript
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';

// ✅ Define schema with Zod
const bookingSchema = z.object({
  courtId: z.string().min(1, 'Court is required'),
  date: z.string().refine((val) => new Date(val) > new Date(), {
    message: 'Date must be in the future',
  }),
  startTime: z.string().regex(/^([01]\d|2[0-3]):([0-5]\d)$/, 'Invalid time format'),
  endTime: z.string().regex(/^([01]\d|2[0-3]):([0-5]\d)$/, 'Invalid time format'),
  notes: z.string().max(500).optional(),
}).refine((data) => data.startTime < data.endTime, {
  message: 'End time must be after start time',
  path: ['endTime'],
});

type BookingFormData = z.infer<typeof bookingSchema>;

// ✅ Form component with validation
function BookingForm({ onSubmit }: { onSubmit: (data: BookingFormData) => void }) {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<BookingFormData>({
    resolver: zodResolver(bookingSchema),
    defaultValues: {
      courtId: '',
      date: '',
      startTime: '',
      endTime: '',
      notes: '',
    },
  });

  return (
    <form onSubmit={handleSubmit(onSubmit)}>
      <FormField label="Court" error={errors.courtId?.message}>
        <select {...register('courtId')}>
          <option value="">Select a court</option>
          {/* options */}
        </select>
      </FormField>

      <FormField label="Date" error={errors.date?.message}>
        <input type="date" {...register('date')} />
      </FormField>

      <FormField label="Start Time" error={errors.startTime?.message}>
        <input type="time" {...register('startTime')} />
      </FormField>

      <FormField label="End Time" error={errors.endTime?.message}>
        <input type="time" {...register('endTime')} />
      </FormField>

      <FormField label="Notes" error={errors.notes?.message}>
        <textarea {...register('notes')} />
      </FormField>

      <Button type="submit" loading={isSubmitting}>
        Create Booking
      </Button>
    </form>
  );
}
```


## 6. Component Patterns

### Component Types

| Type | Purpose | Example |
|------|---------|---------|
| Page | Route entry point, data fetching | `BookingsPage`, `DashboardPage` |
| Container | Business logic, state management | `BookingListContainer` |
| Presentational | Pure UI, receives props | `BookingCard`, `Button` |
| Layout | Page structure | `DashboardLayout`, `Sidebar` |
| Compound | Related components that work together | `Table`, `Table.Header`, `Table.Row` |

### Compound Components Pattern

```typescript
// ✅ Compound components for complex UI
type TableContextValue = {
  sortColumn: string | null;
  sortDirection: 'asc' | 'desc';
  onSort: (column: string) => void;
};

const TableContext = createContext<TableContextValue | null>(null);

function Table({ children, ...props }: TableProps) {
  const [sortColumn, setSortColumn] = useState<string | null>(null);
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('asc');

  const onSort = (column: string) => {
    if (sortColumn === column) {
      setSortDirection((d) => (d === 'asc' ? 'desc' : 'asc'));
    } else {
      setSortColumn(column);
      setSortDirection('asc');
    }
  };

  return (
    <TableContext value={{ sortColumn, sortDirection, onSort }}>
      <table {...props}>{children}</table>
    </TableContext>
  );
}

function TableHeader({ column, children }: TableHeaderProps) {
  const ctx = use(TableContext);
  if (!ctx) throw new Error('TableHeader must be used within Table');

  return (
    <th onClick={() => ctx.onSort(column)}>
      {children}
      {ctx.sortColumn === column && (ctx.sortDirection === 'asc' ? '↑' : '↓')}
    </th>
  );
}

// Export as compound
Table.Header = TableHeader;
Table.Body = TableBody;
Table.Row = TableRow;
Table.Cell = TableCell;

// Usage
<Table>
  <thead>
    <tr>
      <Table.Header column="name">Name</Table.Header>
      <Table.Header column="date">Date</Table.Header>
    </tr>
  </thead>
  <Table.Body>
    {data.map((item) => (
      <Table.Row key={item.id}>
        <Table.Cell>{item.name}</Table.Cell>
        <Table.Cell>{item.date}</Table.Cell>
      </Table.Row>
    ))}
  </Table.Body>
</Table>
```

### Error Boundaries

```typescript
import { Component, ErrorInfo, ReactNode } from 'react';

type ErrorBoundaryProps = {
  children: ReactNode;
  fallback?: ReactNode;
  onError?: (error: Error, errorInfo: ErrorInfo) => void;
};

type ErrorBoundaryState = {
  hasError: boolean;
  error: Error | null;
};

class ErrorBoundary extends Component<ErrorBoundaryProps, ErrorBoundaryState> {
  state: ErrorBoundaryState = { hasError: false, error: null };

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    this.props.onError?.(error, errorInfo);
    console.error('Error caught by boundary:', error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return this.props.fallback ?? (
        <div role="alert">
          <h2>Something went wrong</h2>
          <button onClick={() => this.setState({ hasError: false, error: null })}>
            Try again
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}

// Usage
<ErrorBoundary fallback={<ErrorFallback />} onError={logToService}>
  <BookingList />
</ErrorBoundary>
```

## 7. Performance Optimization

### React Compiler (React 19)

React 19's compiler automatically handles most memoization. Manual optimization is rarely needed.

```typescript
// ❌ Usually unnecessary in React 19
const MemoizedComponent = memo(MyComponent);
const memoizedValue = useMemo(() => expensiveCalc(data), [data]);
const memoizedCallback = useCallback(() => handleClick(), []);

// ✅ React 19 - Just write normal code
function MyComponent({ data }) {
  const processed = expensiveCalc(data); // Compiler optimizes this
  const handleClick = () => { /* ... */ }; // Compiler stabilizes this
  return <div onClick={handleClick}>{processed}</div>;
}
```


### When Manual Optimization Is Still Needed

```typescript
// ✅ Virtualization for long lists
import { useVirtualizer } from '@tanstack/react-virtual';

function VirtualBookingList({ bookings }: { bookings: Booking[] }) {
  const parentRef = useRef<HTMLDivElement>(null);

  const virtualizer = useVirtualizer({
    count: bookings.length,
    getScrollElement: () => parentRef.current,
    estimateSize: () => 72,
  });

  return (
    <div ref={parentRef} style={{ height: '600px', overflow: 'auto' }}>
      <div style={{ height: `${virtualizer.getTotalSize()}px`, position: 'relative' }}>
        {virtualizer.getVirtualItems().map((virtualItem) => (
          <div
            key={virtualItem.key}
            style={{
              position: 'absolute',
              top: 0,
              left: 0,
              width: '100%',
              transform: `translateY(${virtualItem.start}px)`,
            }}
          >
            <BookingCard booking={bookings[virtualItem.index]} />
          </div>
        ))}
      </div>
    </div>
  );
}

// ✅ Code splitting with lazy loading
import { lazy, Suspense } from 'react';

const BookingAnalytics = lazy(() => import('./BookingAnalytics'));
const UserManagement = lazy(() => import('./UserManagement'));

function AdminRoutes() {
  return (
    <Suspense fallback={<PageSkeleton />}>
      <Routes>
        <Route path="/analytics" element={<BookingAnalytics />} />
        <Route path="/users" element={<UserManagement />} />
      </Routes>
    </Suspense>
  );
}

// ✅ Concurrent features for responsive UI
import { useTransition, useDeferredValue } from 'react';

function SearchableBookingList() {
  const [query, setQuery] = useState('');
  const [isPending, startTransition] = useTransition();
  const deferredQuery = useDeferredValue(query);

  const handleSearch = (e: ChangeEvent<HTMLInputElement>) => {
    setQuery(e.target.value); // Urgent: update input immediately
    startTransition(() => {
      // Non-urgent: filter can be interrupted
    });
  };

  return (
    <div>
      <input value={query} onChange={handleSearch} />
      {isPending && <Spinner />}
      <BookingList filter={deferredQuery} />
    </div>
  );
}
```

### Resource Preloading (React 19)

```typescript
import { preload, prefetchDNS, preconnect } from 'react-dom';

function BookingDetailPage({ bookingId }: { bookingId: string }) {
  useEffect(() => {
    // Preload related resources
    preload(`/api/bookings/${bookingId}/history`, { as: 'fetch' });
    preconnect('https://maps.googleapis.com');
  }, [bookingId]);

  return <BookingDetail id={bookingId} />;
}
```

## 8. Testing Standards

### Test Pyramid

```
        /\
       /E2E\      ← Few: Playwright (critical user flows)
      /------\
     /Integr.\   ← Some: Component + API integration
    /----------\
   /   Unit     \ ← Many: Vitest + React Testing Library
  /--------------\
```

### Vitest + React Testing Library Setup

```typescript
// vitest.config.ts
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: './src/test/setup.ts',
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html'],
      exclude: ['node_modules/', 'src/test/'],
    },
  },
});

// src/test/setup.ts
import { cleanup } from '@testing-library/react';
import { afterEach } from 'vitest';
import '@testing-library/jest-dom';

afterEach(() => {
  cleanup();
});
```

### Testing Best Practices

```typescript
import { render, screen, waitFor } from '@testing-library/react';
import { userEvent } from '@testing-library/user-event';
import { describe, it, expect, vi } from 'vitest';

// ✅ Test user behavior, not implementation
describe('BookingForm', () => {
  it('should submit form with valid data', async () => {
    const user = userEvent.setup();
    const onSubmit = vi.fn();

    render(<BookingForm onSubmit={onSubmit} />);

    await user.selectOptions(screen.getByLabelText(/court/i), 'court-1');
    await user.type(screen.getByLabelText(/date/i), '2026-03-15');
    await user.type(screen.getByLabelText(/start time/i), '10:00');
    await user.type(screen.getByLabelText(/end time/i), '11:00');
    await user.click(screen.getByRole('button', { name: /create/i }));

    expect(onSubmit).toHaveBeenCalledWith({
      courtId: 'court-1',
      date: '2026-03-15',
      startTime: '10:00',
      endTime: '11:00',
    });
  });

  it('should show validation error for past date', async () => {
    const user = userEvent.setup();

    render(<BookingForm onSubmit={vi.fn()} />);

    await user.type(screen.getByLabelText(/date/i), '2020-01-01');
    await user.click(screen.getByRole('button', { name: /create/i }));

    expect(screen.getByText(/date must be in the future/i)).toBeInTheDocument();
  });
});

// ✅ Test async components with Suspense
describe('BookingList', () => {
  it('should display bookings after loading', async () => {
    const mockBookings = [
      { id: '1', courtName: 'Court A', date: '2026-03-15' },
      { id: '2', courtName: 'Court B', date: '2026-03-16' },
    ];

    vi.spyOn(api, 'getBookings').mockResolvedValue(mockBookings);

    render(
      <QueryClientProvider client={queryClient}>
        <BookingList />
      </QueryClientProvider>
    );

    expect(screen.getByText(/loading/i)).toBeInTheDocument();

    await waitFor(() => {
      expect(screen.getByText('Court A')).toBeInTheDocument();
      expect(screen.getByText('Court B')).toBeInTheDocument();
    });
  });
});

// ✅ Test custom hooks
import { renderHook, waitFor } from '@testing-library/react';

describe('useBookings', () => {
  it('should fetch and return bookings', async () => {
    vi.spyOn(api, 'getBookings').mockResolvedValue([{ id: '1' }]);

    const { result } = renderHook(() => useBookings({}), {
      wrapper: QueryClientProvider,
    });

    expect(result.current.isLoading).toBe(true);

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false);
    });

    expect(result.current.data).toHaveLength(1);
  });
});
```


## 9. Security Best Practices

### XSS Prevention

```typescript
// ✅ React automatically escapes values in JSX
function UserGreeting({ name }: { name: string }) {
  return <div>Hello, {name}!</div>; // Safe - escaped
}

// ❌ DANGEROUS - Never use without sanitization
function RichContent({ html }: { html: string }) {
  return <div dangerouslySetInnerHTML={{ __html: html }} />; // XSS risk!
}

// ✅ SAFE - Sanitize with DOMPurify
import DOMPurify from 'dompurify';

function RichContent({ html }: { html: string }) {
  const sanitized = DOMPurify.sanitize(html, {
    ALLOWED_TAGS: ['p', 'b', 'i', 'em', 'strong', 'a'],
    ALLOWED_ATTR: ['href'],
  });
  return <div dangerouslySetInnerHTML={{ __html: sanitized }} />;
}

// ✅ Validate URLs before rendering
function SafeLink({ url, children }: { url: string; children: ReactNode }) {
  const isValidUrl = (url: string) => {
    try {
      const parsed = new URL(url);
      return ['http:', 'https:', 'mailto:'].includes(parsed.protocol);
    } catch {
      return false;
    }
  };

  if (!isValidUrl(url)) {
    console.warn('Invalid URL blocked:', url);
    return <span>{children}</span>;
  }

  return <a href={url}>{children}</a>;
}
```

### Authentication & Authorization

```typescript
// ✅ Protected routes
function ProtectedRoute({ children, requiredRole }: ProtectedRouteProps) {
  const { user, isLoading } = useAuth();

  if (isLoading) return <PageSkeleton />;

  if (!user) {
    return <Navigate to="/login" replace />;
  }

  if (requiredRole && user.role !== requiredRole) {
    return <Navigate to="/unauthorized" replace />;
  }

  return <>{children}</>;
}

// ✅ Permission-based UI
function BookingActions({ booking }: { booking: Booking }) {
  const { hasPermission } = usePermissions();

  return (
    <div>
      {hasPermission('booking:edit') && (
        <Button onClick={() => editBooking(booking.id)}>Edit</Button>
      )}
      {hasPermission('booking:delete') && (
        <Button variant="danger" onClick={() => deleteBooking(booking.id)}>
          Delete
        </Button>
      )}
    </div>
  );
}

// ✅ Secure token storage (use HTTPOnly cookies, not localStorage)
// Token should be set by server with:
// Set-Cookie: token=xxx; HttpOnly; Secure; SameSite=Strict

// ✅ API client with credentials
const api = axios.create({
  baseURL: import.meta.env.VITE_API_URL,
  withCredentials: true, // Send cookies
});
```

### Input Validation

```typescript
// ✅ Client-side validation (UX) + Server-side validation (security)
const bookingSchema = z.object({
  courtId: z.string().uuid('Invalid court ID'),
  date: z.string().refine((val) => {
    const date = new Date(val);
    return date > new Date() && date < addMonths(new Date(), 3);
  }, 'Date must be within the next 3 months'),
  startTime: z.string().regex(/^([01]\d|2[0-3]):([0-5]\d)$/),
  endTime: z.string().regex(/^([01]\d|2[0-3]):([0-5]\d)$/),
});

// Server should ALWAYS validate again - never trust client
```

## 10. Code Style & Linting

### ESLint Configuration

```javascript
// eslint.config.js
import js from '@eslint/js';
import typescript from '@typescript-eslint/eslint-plugin';
import typescriptParser from '@typescript-eslint/parser';
import react from 'eslint-plugin-react';
import reactHooks from 'eslint-plugin-react-hooks';
import jsxA11y from 'eslint-plugin-jsx-a11y';

export default [
  js.configs.recommended,
  {
    files: ['**/*.{ts,tsx}'],
    languageOptions: {
      parser: typescriptParser,
      parserOptions: {
        project: './tsconfig.json',
      },
    },
    plugins: {
      '@typescript-eslint': typescript,
      react,
      'react-hooks': reactHooks,
      'jsx-a11y': jsxA11y,
    },
    rules: {
      // TypeScript
      '@typescript-eslint/no-unused-vars': 'error',
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/consistent-type-definitions': ['error', 'type'],
      '@typescript-eslint/prefer-nullish-coalescing': 'error',
      
      // React
      'react/jsx-no-leaked-render': 'error',
      'react-hooks/rules-of-hooks': 'error',
      'react-hooks/exhaustive-deps': 'warn',
      
      // Accessibility
      'jsx-a11y/alt-text': 'error',
      'jsx-a11y/anchor-is-valid': 'error',
      'jsx-a11y/click-events-have-key-events': 'error',
      'jsx-a11y/no-static-element-interactions': 'error',
    },
  },
];
```

### Prettier Configuration

```json
{
  "semi": true,
  "singleQuote": true,
  "tabWidth": 2,
  "trailingComma": "es5",
  "printWidth": 100,
  "plugins": ["prettier-plugin-tailwindcss"]
}
```


## 11. Technology Stack

| Category | Technology | Version |
|----------|-----------|---------|
| Framework | React | 19.x |
| Language | TypeScript | 5.x |
| Build Tool | Vite | 6.x |
| Routing | React Router | 7.x |
| Server State | TanStack Query | 5.x |
| Client State | Zustand | 5.x |
| Forms | React Hook Form + Zod | 7.x + 3.x |
| Styling | Tailwind CSS | 4.x |
| UI Components | Radix UI / shadcn/ui | Latest |
| HTTP Client | Axios / Fetch | Latest |
| Testing | Vitest + React Testing Library | Latest |
| E2E Testing | Playwright | Latest |
| Linting | ESLint + Prettier | Latest |
| Icons | Lucide React | Latest |
| Date Handling | date-fns | Latest |
| Charts | Recharts / TanStack Charts | Latest |

## 12. Quick Reference - Decision Rules

| When you need to... | Do this |
|---------------------|---------|
| Fetch server data | Use TanStack Query with query key factory |
| Store global UI state | Use Zustand with selectors |
| Handle forms | Use React Hook Form + Zod validation |
| Create reusable UI | Build compound components |
| Handle async UI | Use Suspense + use() hook |
| Optimize lists | Use @tanstack/react-virtual |
| Split code | Use lazy() + Suspense |
| Test components | Use Vitest + React Testing Library |
| Test E2E flows | Use Playwright |
| Style components | Use Tailwind CSS utility classes |
| Handle errors | Use Error Boundaries |
| Protect routes | Use ProtectedRoute wrapper |
| Validate input | Client: Zod, Server: Always re-validate |
| Store auth tokens | HTTPOnly cookies (server-set) |

## 13. Reference Repositories

| Repository | Stars | Focus Area |
|-----------|-------|-----------|
| [alan2207/bulletproof-react](https://github.com/alan2207/bulletproof-react) | ~29k ⭐ | Project structure, best practices |
| [mkosir/typescript-style-guide](https://github.com/mkosir/typescript-style-guide) | ~1k ⭐ | TypeScript conventions |
| [TanStack/query](https://github.com/TanStack/query) | ~43k ⭐ | Server state management |
| [pmndrs/zustand](https://github.com/pmndrs/zustand) | ~48k ⭐ | Client state management |
| [react-hook-form/react-hook-form](https://github.com/react-hook-form/react-hook-form) | ~42k ⭐ | Form handling |
| [colinhacks/zod](https://github.com/colinhacks/zod) | ~35k ⭐ | Schema validation |
| [shadcn/ui](https://github.com/shadcn/ui) | ~75k ⭐ | UI components |
| [TailAdmin/free-react-tailwind-admin-dashboard](https://github.com/TailAdmin/free-react-tailwind-admin-dashboard) | ~2k ⭐ | Admin dashboard template |

## 14. API Client Setup

### Axios Configuration

```typescript
// src/lib/api-client.ts
import axios, { AxiosError, AxiosRequestConfig } from 'axios';

const API_URL = import.meta.env.VITE_API_URL;

export const apiClient = axios.create({
  baseURL: API_URL,
  withCredentials: true,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Request interceptor for auth
apiClient.interceptors.request.use((config) => {
  // Token is handled via HTTPOnly cookies, no manual header needed
  return config;
});

// Response interceptor for error handling
apiClient.interceptors.response.use(
  (response) => response,
  async (error: AxiosError) => {
    if (error.response?.status === 401) {
      // Redirect to login or refresh token
      window.location.href = '/login';
    }
    return Promise.reject(error);
  }
);

// Type-safe API functions
export async function get<T>(url: string, config?: AxiosRequestConfig): Promise<T> {
  const response = await apiClient.get<T>(url, config);
  return response.data;
}

export async function post<T, D = unknown>(url: string, data?: D, config?: AxiosRequestConfig): Promise<T> {
  const response = await apiClient.post<T>(url, data, config);
  return response.data;
}

export async function put<T, D = unknown>(url: string, data?: D, config?: AxiosRequestConfig): Promise<T> {
  const response = await apiClient.put<T>(url, data, config);
  return response.data;
}

export async function del<T>(url: string, config?: AxiosRequestConfig): Promise<T> {
  const response = await apiClient.delete<T>(url, config);
  return response.data;
}
```

### API Error Handling

```typescript
// src/lib/api-error.ts
import { AxiosError } from 'axios';

type ApiErrorResponse = {
  message: string;
  errors?: Record<string, string[]>;
  status: number;
};

export class ApiError extends Error {
  status: number;
  errors?: Record<string, string[]>;

  constructor(message: string, status: number, errors?: Record<string, string[]>) {
    super(message);
    this.name = 'ApiError';
    this.status = status;
    this.errors = errors;
  }

  static fromAxiosError(error: AxiosError<ApiErrorResponse>): ApiError {
    const message = error.response?.data?.message || 'An unexpected error occurred';
    const status = error.response?.status || 500;
    const errors = error.response?.data?.errors;
    return new ApiError(message, status, errors);
  }
}

// Usage in API calls
export async function createBooking(data: CreateBookingData): Promise<Booking> {
  try {
    return await post<Booking>('/bookings', data);
  } catch (error) {
    if (error instanceof AxiosError) {
      throw ApiError.fromAxiosError(error);
    }
    throw error;
  }
}
```

## 15. Environment Configuration

### Environment Variables

```typescript
// src/config/env.ts
import { z } from 'zod';

const envSchema = z.object({
  VITE_API_URL: z.string().url(),
  VITE_APP_NAME: z.string().default('Court Booking Admin'),
  VITE_ENABLE_MOCK: z.string().transform((v) => v === 'true').default('false'),
});

// Validate at startup
const parsed = envSchema.safeParse(import.meta.env);

if (!parsed.success) {
  console.error('❌ Invalid environment variables:', parsed.error.flatten().fieldErrors);
  throw new Error('Invalid environment variables');
}

export const env = parsed.data;
```

### Vite Configuration

```typescript
// vite.config.ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import path from 'path';

export default defineConfig({
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    port: 3000,
    proxy: {
      '/api': {
        target: 'http://localhost:8080',
        changeOrigin: true,
      },
    },
  },
});
```

### TypeScript Path Aliases

```json
// tsconfig.json
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "baseUrl": ".",
    "paths": {
      "@/*": ["./src/*"]
    }
  },
  "include": ["src"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
```

## 16. Routing Setup

### React Router Configuration

```typescript
// src/app/routes/index.tsx
import { createBrowserRouter, RouterProvider } from 'react-router-dom';
import { lazy, Suspense } from 'react';
import { DashboardLayout } from '@/components/layout/DashboardLayout';
import { ProtectedRoute } from '@/features/auth/components/ProtectedRoute';
import { PageSkeleton } from '@/components/feedback/PageSkeleton';

// Lazy load pages
const DashboardPage = lazy(() => import('@/features/dashboard/DashboardPage'));
const BookingsPage = lazy(() => import('@/features/bookings/BookingsPage'));
const BookingDetailPage = lazy(() => import('@/features/bookings/BookingDetailPage'));
const CourtsPage = lazy(() => import('@/features/courts/CourtsPage'));
const UsersPage = lazy(() => import('@/features/users/UsersPage'));
const LoginPage = lazy(() => import('@/features/auth/LoginPage'));
const NotFoundPage = lazy(() => import('@/components/feedback/NotFoundPage'));

const router = createBrowserRouter([
  {
    path: '/login',
    element: (
      <Suspense fallback={<PageSkeleton />}>
        <LoginPage />
      </Suspense>
    ),
  },
  {
    path: '/',
    element: (
      <ProtectedRoute>
        <DashboardLayout />
      </ProtectedRoute>
    ),
    children: [
      {
        index: true,
        element: (
          <Suspense fallback={<PageSkeleton />}>
            <DashboardPage />
          </Suspense>
        ),
      },
      {
        path: 'bookings',
        element: (
          <Suspense fallback={<PageSkeleton />}>
            <BookingsPage />
          </Suspense>
        ),
      },
      {
        path: 'bookings/:id',
        element: (
          <Suspense fallback={<PageSkeleton />}>
            <BookingDetailPage />
          </Suspense>
        ),
      },
      {
        path: 'courts',
        element: (
          <Suspense fallback={<PageSkeleton />}>
            <CourtsPage />
          </Suspense>
        ),
      },
      {
        path: 'users',
        element: (
          <ProtectedRoute requiredRole="admin">
            <Suspense fallback={<PageSkeleton />}>
              <UsersPage />
            </Suspense>
          </ProtectedRoute>
        ),
      },
    ],
  },
  {
    path: '*',
    element: (
      <Suspense fallback={<PageSkeleton />}>
        <NotFoundPage />
      </Suspense>
    ),
  },
]);

export function AppRouter() {
  return <RouterProvider router={router} />;
}
```

## 17. App Providers Setup

### Provider Composition

```typescript
// src/app/providers/index.tsx
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { ReactQueryDevtools } from '@tanstack/react-query-devtools';
import { ReactNode } from 'react';
import { ErrorBoundary } from '@/components/feedback/ErrorBoundary';
import { Toaster } from '@/components/ui/Toaster';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 5 * 60 * 1000, // 5 minutes
      retry: 1,
      refetchOnWindowFocus: false,
    },
    mutations: {
      retry: 0,
    },
  },
});

type AppProvidersProps = {
  children: ReactNode;
};

export function AppProviders({ children }: AppProvidersProps) {
  return (
    <ErrorBoundary>
      <QueryClientProvider client={queryClient}>
        {children}
        <Toaster />
        <ReactQueryDevtools initialIsOpen={false} />
      </QueryClientProvider>
    </ErrorBoundary>
  );
}
```

### Main Entry Point

```typescript
// src/main.tsx
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { AppProviders } from '@/app/providers';
import { AppRouter } from '@/app/routes';
import '@/styles/globals.css';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <AppProviders>
      <AppRouter />
    </AppProviders>
  </StrictMode>
);
```

## 18. Anti-Patterns to Avoid

| Anti-Pattern | Why It's Bad | Better Approach |
|--------------|--------------|-----------------|
| Props drilling through many levels | Hard to maintain, refactor | Use Context or Zustand |
| useEffect for derived state | Unnecessary re-renders | Calculate directly or useMemo |
| Storing server state in useState | Stale data, no caching | Use TanStack Query |
| localStorage for auth tokens | XSS vulnerability | HTTPOnly cookies |
| Testing implementation details | Brittle tests | Test user behavior |
| One massive component | Hard to test, maintain | Split into smaller components |
| any type | Defeats TypeScript purpose | Use proper types or unknown |
| Inline styles everywhere | Hard to maintain | Use Tailwind or CSS modules |
| Catching errors silently | Hides bugs | Log and display appropriately |
| Prop spreading without filtering | Passes unwanted props | Destructure and spread rest |

---

> **Note**: This guide is based on patterns from bulletproof-react, TypeScript Style Guide, and React 19 official documentation. Adapt as needed for your specific requirements while maintaining consistency across the codebase.

## 19. Package.json Scripts

### Recommended Scripts

```json
{
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "preview": "vite preview",
    "lint": "eslint . --ext ts,tsx --report-unused-disable-directives --max-warnings 0",
    "lint:fix": "eslint . --ext ts,tsx --fix",
    "format": "prettier --write \"src/**/*.{ts,tsx,css,json}\"",
    "format:check": "prettier --check \"src/**/*.{ts,tsx,css,json}\"",
    "test": "vitest",
    "test:ui": "vitest --ui",
    "test:coverage": "vitest run --coverage",
    "test:e2e": "playwright test",
    "type-check": "tsc --noEmit",
    "prepare": "husky install"
  }
}
```

## 20. File Naming Conventions

| File Type | Convention | Example |
|-----------|------------|---------|
| Components | PascalCase | `BookingCard.tsx` |
| Hooks | camelCase with use prefix | `useBookings.ts` |
| Utils | camelCase | `formatDate.ts` |
| Types | camelCase or index | `types.ts`, `index.ts` |
| Constants | camelCase | `constants.ts` |
| Tests | Same as source + .test | `BookingCard.test.tsx` |
| Styles | Same as component | `BookingCard.module.css` |
| API | camelCase verb + noun | `getBookings.ts`, `createBooking.ts` |

## 21. Git Commit Conventions

Use conventional commits for clear history:

```
feat: add booking calendar view
fix: resolve date picker timezone issue
refactor: extract booking form validation
test: add unit tests for useBookings hook
docs: update README with setup instructions
chore: upgrade dependencies
style: format code with prettier
```

---

> **Implementation Checklist for Agent**:
> 1. ✅ Set up Vite + React 19 + TypeScript project
> 2. ✅ Configure path aliases (@/)
> 3. ✅ Install and configure TanStack Query
> 4. ✅ Set up Zustand for auth/UI state
> 5. ✅ Configure React Router with lazy loading
> 6. ✅ Set up Tailwind CSS + shadcn/ui
> 7. ✅ Configure ESLint + Prettier
> 8. ✅ Set up Vitest + React Testing Library
> 9. ✅ Create feature-based folder structure
> 10. ✅ Implement API client with error handling
