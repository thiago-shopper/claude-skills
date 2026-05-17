# frontend-modules

Frontend folder layout — module-per-page, lazy-loaded, two main layouts, shared kernel. Inspired by `kdb-tech/kdb-tech-ui`.

This layout is **not configurable** — every frontend scaffold uses it. Only the module list and whether the auth module is present vary.

---

## The shape

```
src/
├── modules/                  # one folder per page
│   ├── home/
│   │   ├── HomePage.tsx
│   │   ├── components/
│   │   ├── hooks/
│   │   └── index.ts          # default-export lazy() wrapper
│   ├── settings/
│   │   ├── SettingsPage.tsx
│   │   └── index.ts
│   └── auth/                 # only if auth=yes — see auth-layer.md
├── layouts/
│   ├── MainLayout.tsx        # default chrome
│   └── AuthLayout.tsx        # auth pages chrome
├── shared/
│   ├── components/           # reusable UI (Button, Input, Modal, …)
│   ├── hooks/                # reusable hooks (useFetch, …)
│   ├── lib/                  # api client, formatters, utils
│   └── auth/                 # only if auth=yes — see auth-layer.md
├── routes/
│   └── index.tsx             # route map: layouts × modules
├── styles/
│   └── index.css
├── App.tsx                   # mounts router (+ AuthProvider if auth=yes)
└── main.tsx                  # from Vite
```

---

## The lazy export contract

Every module's `index.ts` looks like:

```ts
import { lazy } from 'react';

export default lazy(() => import('./HomePage'));
```

That's it. The route map (below) imports modules via dynamic `import()` so each becomes its own chunk in the production bundle.

The page component is plain — no special wrapper:

```tsx
// src/modules/home/HomePage.tsx
export default function HomePage() {
  return (
    <section>
      <h1>{{name}}</h1>
      <p>Hello from Vite + React + TypeScript.</p>
    </section>
  );
}
```

---

## Layouts

Two layouts. Pick the one that fits the page; everything that doesn't fit goes in a new layout file (which you only add when needed — don't preempt).

### `src/layouts/MainLayout.tsx`

```tsx
import { Outlet } from 'react-router-dom';

export default function MainLayout() {
  return (
    <div className="layout layout--main">
      <header className="layout__header">
        <nav>{/* primary nav */}</nav>
      </header>
      <main className="layout__content">
        <Outlet />
      </main>
      <footer className="layout__footer">{/* footer */}</footer>
    </div>
  );
}
```

### `src/layouts/AuthLayout.tsx`

```tsx
import { Outlet } from 'react-router-dom';

export default function AuthLayout() {
  return (
    <div className="layout layout--auth">
      <div className="layout--auth__card">
        <Outlet />
      </div>
    </div>
  );
}
```

The CSS classes are placeholders — real styling lives in `src/styles/index.css` (or per-module CSS modules if the user adds them later).

---

## The route map

`src/routes/index.tsx` is the single place where modules meet layouts. Two top-level routes: one wrapped in `MainLayout`, one wrapped in `AuthLayout`. Each child route loads a lazy module.

### Without auth

```tsx
import { Suspense } from 'react';
import { Routes, Route } from 'react-router-dom';
import MainLayout from '../layouts/MainLayout.js';

import HomeModule from '../modules/home/index.js';
import SettingsModule from '../modules/settings/index.js';

function PageFallback() {
  return <div>Loading…</div>;
}

export function AppRoutes() {
  return (
    <Suspense fallback={<PageFallback />}>
      <Routes>
        <Route element={<MainLayout />}>
          <Route path="/" element={<HomeModule />} />
          <Route path="/settings" element={<SettingsModule />} />
        </Route>
      </Routes>
    </Suspense>
  );
}
```

### With auth

```tsx
import { Suspense } from 'react';
import { Routes, Route, Navigate } from 'react-router-dom';
import MainLayout from '../layouts/MainLayout.js';
import AuthLayout from '../layouts/AuthLayout.js';
import { ProtectedRoute } from '../shared/auth/ProtectedRoute.js';

import HomeModule from '../modules/home/index.js';
import SettingsModule from '../modules/settings/index.js';
import { LoginModule, RegisterModule, ForgotPasswordModule } from '../modules/auth/index.js';

function PageFallback() {
  return <div>Loading…</div>;
}

export function AppRoutes() {
  return (
    <Suspense fallback={<PageFallback />}>
      <Routes>
        {/* Auth pages — no auth required */}
        <Route element={<AuthLayout />}>
          <Route path="/login" element={<LoginModule />} />
          <Route path="/register" element={<RegisterModule />} />
          <Route path="/forgot" element={<ForgotPasswordModule />} />
        </Route>

        {/* Everything else — auth required */}
        <Route
          element={
            <ProtectedRoute>
              <MainLayout />
            </ProtectedRoute>
          }
        >
          <Route path="/" element={<HomeModule />} />
          <Route path="/settings" element={<SettingsModule />} />
        </Route>

        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </Suspense>
  );
}
```

`ProtectedRoute` wraps the layout once; every child route inherits the guard. `<Outlet />` in the layout renders the matched module.

---

## Shared kernel

`src/shared/` holds anything that's used across more than one module. The skill seeds it with two concrete examples so it's not an empty folder:

### `src/shared/components/Button.tsx`

```tsx
import type { ButtonHTMLAttributes, ReactNode } from 'react';

type Props = ButtonHTMLAttributes<HTMLButtonElement> & {
  children: ReactNode;
  variant?: 'primary' | 'ghost';
};

export function Button({ children, variant = 'primary', ...rest }: Props) {
  return (
    <button className={`btn btn--${variant}`} {...rest}>
      {children}
    </button>
  );
}
```

### `src/shared/hooks/useFetch.ts`

```ts
import { useEffect, useState } from 'react';
import { api } from '../lib/api.js';

type State<T> = { data: T | null; error: Error | null; loading: boolean };

export function useFetch<T>(path: string): State<T> {
  const [state, setState] = useState<State<T>>({ data: null, error: null, loading: true });

  useEffect(() => {
    let cancelled = false;
    api
      .get<T>(path)
      .then((data) => {
        if (!cancelled) setState({ data, error: null, loading: false });
      })
      .catch((error: Error) => {
        if (!cancelled) setState({ data: null, error, loading: false });
      });
    return () => {
      cancelled = true;
    };
  }, [path]);

  return state;
}
```

### `src/shared/lib/api.ts`

```ts
const BASE_URL = (import.meta.env.VITE_API_URL as string | undefined) ?? '';

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${BASE_URL}${path}`, {
    ...init,
    headers: { 'Content-Type': 'application/json', ...(init?.headers ?? {}) },
    credentials: 'include',
  });
  if (!res.ok) {
    throw new Error(`HTTP ${res.status}: ${await res.text()}`);
  }
  return (await res.json()) as T;
}

export const api = {
  get: <T>(path: string) => request<T>(path),
  post: <T>(path: string, body: unknown) =>
    request<T>(path, { method: 'POST', body: JSON.stringify(body) }),
  put: <T>(path: string, body: unknown) =>
    request<T>(path, { method: 'PUT', body: JSON.stringify(body) }),
  delete: <T>(path: string) => request<T>(path, { method: 'DELETE' }),
};
```

---

## Styles

`src/styles/index.css` is intentionally minimal — a CSS reset plus tokens for the layout classes:

```css
*,
*::before,
*::after {
  box-sizing: border-box;
}

html,
body,
#root {
  margin: 0;
  height: 100%;
  font-family: system-ui, -apple-system, 'Segoe UI', Roboto, sans-serif;
  background: #fafafa;
  color: #111;
}

.layout--main {
  display: grid;
  grid-template-rows: auto 1fr auto;
  min-height: 100vh;
}

.layout--main__header,
.layout--main__footer {
  padding: 1rem 1.5rem;
  background: #fff;
  border-bottom: 1px solid #eee;
}

.layout--auth {
  display: grid;
  place-items: center;
  min-height: 100vh;
  padding: 2rem;
}

.layout--auth__card {
  width: 100%;
  max-width: 360px;
  padding: 2rem;
  background: #fff;
  border: 1px solid #eee;
  border-radius: 8px;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.04);
}

.btn {
  font: inherit;
  padding: 0.5rem 1rem;
  border-radius: 6px;
  border: 1px solid transparent;
  cursor: pointer;
}

.btn--primary {
  background: #111;
  color: #fff;
}

.btn--ghost {
  background: transparent;
  color: #111;
  border-color: #ddd;
}
```

Wire it in `src/main.tsx`:
```ts
import './styles/index.css';
```

---

## Tests

`tests/setup.ts` is already shown in [file-templates.md](file-templates.md). Per-module test:

### `tests/modules/home/HomePage.test.tsx`

```tsx
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import HomePage from '../../../src/modules/home/HomePage.js';

describe('HomePage', () => {
  it('renders the project name', () => {
    render(<HomePage />);
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('{{name}}');
  });
});
```

---

## How to add a new module (instructions for CLAUDE.md)

```
1. mkdir src/modules/<name>
2. Create src/modules/<name>/<Name>Page.tsx with a default export
3. Create src/modules/<name>/index.ts:
     import { lazy } from 'react';
     export default lazy(() => import('./<Name>Page'));
4. Register it in src/routes/index.tsx under MainLayout (or AuthLayout if it's an auth page)
5. Add tests/modules/<name>/<Name>Page.test.tsx
```

That's the full checklist — five lines.
