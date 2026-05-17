# auth-layer

The auth layer is **pluggable**: the layer (context, middleware, hooks, types, route guards) is identical across all auth methods. The only file that changes is the adapter under `shared/auth/adapters/`.

Generated only when the user picks **JWT**, **Session**, or **OAuth stub** in the Auth question. If the user picks "None", nothing in this file is generated.

---

## The contract

`shared/auth/types.ts` defines the contract that every adapter must satisfy. The same shape is used on both backend and frontend (with platform-specific signatures for the things that genuinely differ — e.g. cookies vs. memory storage).

### Backend `src/shared/auth/types.ts`

```ts
import type { Request, Response } from 'express';

export type User = {
  readonly id: string;
  readonly email: string;
};

export type Session = {
  readonly user: User;
  readonly issuedAt: number;
  readonly expiresAt: number;
};

export interface AuthAdapter {
  /** Verify a request and return the session if valid, null otherwise. */
  verify(req: Request): Promise<Session | null>;
  /** Establish a session for `user` and attach it to the response (cookie, token, etc.). */
  issue(user: User, res: Response): Promise<{ accessToken?: string }>;
  /** Tear down the session (clear cookie, revoke token, etc.). */
  revoke(req: Request, res: Response): Promise<void>;
  /** Refresh an existing session if supported. Throws if not supported. */
  refresh(req: Request, res: Response): Promise<{ accessToken?: string }>;
}
```

### Frontend `src/shared/auth/types.ts`

```ts
export type User = {
  readonly id: string;
  readonly email: string;
};

export type Credentials = {
  email: string;
  password: string;
};

export interface AuthAdapter {
  /** Called once on mount. Returns the current user if a session is active. */
  bootstrap(): Promise<User | null>;
  /** Authenticate with credentials and return the user. */
  login(creds: Credentials): Promise<User>;
  /** Tear down the session and return. */
  logout(): Promise<void>;
  /** Refresh the access token if the adapter supports it. Returns the user (possibly re-fetched). */
  refresh(): Promise<User>;
}
```

These interfaces are **stable** — the layer code calls only these methods. Swapping JWT → Session means rewriting one adapter file, not rewiring modules.

---

## Backend layer files (always the same)

### `src/shared/auth/requireAuth.ts`

```ts
import type { Request, Response, NextFunction } from 'express';
import { authAdapter } from './adapters/index.js';

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      session?: import('./types.js').Session;
    }
  }
}

export async function requireAuth(req: Request, res: Response, next: NextFunction): Promise<void> {
  const session = await authAdapter.verify(req);
  if (!session) {
    res.status(401).json({ error: { code: 'UNAUTHENTICATED', message: 'Login required' } });
    return;
  }
  req.session = session;
  next();
}
```

### `src/shared/auth/adapters/index.ts`

This is the single wire-in point. Replace the import when swapping adapters.

```ts
// Swap this line to change auth method:
//   import { jwtAdapter as authAdapter } from './jwt.adapter.js';
//   import { sessionAdapter as authAdapter } from './session.adapter.js';
//   import { oauthAdapter as authAdapter } from './oauth.adapter.js';
export { jwtAdapter as authAdapter } from './jwt.adapter.js';
```

(The skill writes this file with the user's chosen adapter selected. The other two adapter files are **not** generated.)

---

## Backend module — `src/modules/auth/`

The HTTP surface. Same shape regardless of adapter.

### `src/modules/auth/index.ts`

```ts
import { authRouter } from './auth.routes.js';

export default {
  mountPath: '/auth',
  router: authRouter,
};
```

### `src/modules/auth/auth.routes.ts`

```ts
import { Router } from 'express';
import { authController } from './auth.controller.js';
import { requireAuth } from '../../shared/auth/requireAuth.js';

export const authRouter = Router();
authRouter.post('/login', authController.login);
authRouter.post('/logout', authController.logout);
authRouter.post('/refresh', authController.refresh);
authRouter.get('/me', requireAuth, authController.me);
```

### `src/modules/auth/auth.controller.ts`

```ts
import type { Request, Response } from 'express';
import { authService } from './auth.service.js';
import { loginRequestSchema } from './auth.schema.js';
import { authAdapter } from '../../shared/auth/adapters/index.js';

export const authController = {
  async login(req: Request, res: Response): Promise<void> {
    const parsed = loginRequestSchema.safeParse(req.body);
    if (!parsed.success) {
      res.status(400).json({ error: { code: 'INVALID', message: 'Bad credentials shape' } });
      return;
    }
    const user = await authService.authenticate(parsed.data);
    if (!user) {
      res.status(401).json({ error: { code: 'INVALID_CREDS', message: 'Bad credentials' } });
      return;
    }
    const issued = await authAdapter.issue(user, res);
    res.status(200).json({ user, ...issued });
  },

  async logout(req: Request, res: Response): Promise<void> {
    await authAdapter.revoke(req, res);
    res.status(204).end();
  },

  async refresh(req: Request, res: Response): Promise<void> {
    try {
      const issued = await authAdapter.refresh(req, res);
      res.status(200).json(issued);
    } catch {
      res.status(401).json({ error: { code: 'REFRESH_FAILED', message: 'Cannot refresh' } });
    }
  },

  me(req: Request, res: Response): void {
    res.status(200).json({ user: req.session!.user });
  },
};
```

### `src/modules/auth/auth.service.ts`

```ts
import type { User } from '../../shared/auth/types.js';

type Credentials = { email: string; password: string };

// TODO: replace this stub with real lookup (DB / external IdP / etc.)
const STUB_USERS: Array<{ user: User; password: string }> = [
  { user: { id: 'u1', email: 'demo@example.com' }, password: 'demo' },
];

export const authService = {
  async authenticate(creds: Credentials): Promise<User | null> {
    const match = STUB_USERS.find(
      (entry) => entry.user.email === creds.email && entry.password === creds.password,
    );
    return match ? match.user : null;
  },
};
```

### `src/modules/auth/auth.schema.ts`

```ts
import { z } from 'zod';

export const loginRequestSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

export type LoginRequest = z.infer<typeof loginRequestSchema>;
```

---

## Backend adapters (pick one)

### JWT — `src/shared/auth/adapters/jwt.adapter.ts`

```ts
import jwt from 'jsonwebtoken';
import type { Request, Response } from 'express';
import type { AuthAdapter, Session, User } from '../types.js';
import { env } from '../../../config/env.js';

const ACCESS_TTL_SECONDS = 60 * 15;     // 15 minutes
const REFRESH_TTL_SECONDS = 60 * 60 * 24 * 7; // 7 days

function sign(user: User, ttl: number): string {
  return jwt.sign({ sub: user.id, email: user.email }, env.JWT_SECRET, { expiresIn: ttl });
}

function decode(token: string): Session | null {
  try {
    const payload = jwt.verify(token, env.JWT_SECRET) as jwt.JwtPayload;
    if (!payload.sub || !payload.email) return null;
    return {
      user: { id: payload.sub as string, email: payload.email as string },
      issuedAt: (payload.iat ?? 0) * 1000,
      expiresAt: (payload.exp ?? 0) * 1000,
    };
  } catch {
    return null;
  }
}

export const jwtAdapter: AuthAdapter = {
  async verify(req: Request) {
    const header = req.header('authorization');
    if (!header?.startsWith('Bearer ')) return null;
    return decode(header.slice(7));
  },
  async issue(user: User, res: Response) {
    const accessToken = sign(user, ACCESS_TTL_SECONDS);
    const refreshToken = sign(user, REFRESH_TTL_SECONDS);
    res.cookie('refresh_token', refreshToken, {
      httpOnly: true,
      sameSite: 'strict',
      secure: env.NODE_ENV === 'production',
      maxAge: REFRESH_TTL_SECONDS * 1000,
      path: '/auth/refresh',
    });
    return { accessToken };
  },
  async revoke(_req: Request, res: Response) {
    res.clearCookie('refresh_token', { path: '/auth/refresh' });
  },
  async refresh(req: Request, res: Response) {
    const refreshToken = (req as Request & { cookies?: Record<string, string> }).cookies?.refresh_token;
    if (!refreshToken) throw new Error('no refresh token');
    const decoded = decode(refreshToken);
    if (!decoded) throw new Error('invalid refresh token');
    const accessToken = sign(decoded.user, ACCESS_TTL_SECONDS);
    return { accessToken };
  },
};
```

Required `package.json` additions for JWT:
```json
"dependencies": { "jsonwebtoken": "^9.0.2", "cookie-parser": "^1.4.7" },
"devDependencies": { "@types/jsonwebtoken": "^9.0.7", "@types/cookie-parser": "^1.4.7" }
```

And in `src/app.ts`:
```ts
import cookieParser from 'cookie-parser';
app.use(cookieParser());
```

`env.ts` schema additions: `JWT_SECRET: z.string().min(16), NODE_ENV: z.enum(['development','production','test']).default('development')`.

### Session — `src/shared/auth/adapters/session.adapter.ts`

```ts
import session from 'express-session';
import type { Request, Response } from 'express';
import type { AuthAdapter, Session as AppSession, User } from '../types.js';
import { env } from '../../../config/env.js';

const ONE_WEEK_MS = 1000 * 60 * 60 * 24 * 7;

declare module 'express-session' {
  interface SessionData {
    user?: User;
    issuedAt?: number;
  }
}

export const sessionMiddleware = session({
  secret: env.SESSION_SECRET,
  resave: false,
  saveUninitialized: false,
  cookie: {
    httpOnly: true,
    sameSite: 'lax',
    secure: env.NODE_ENV === 'production',
    maxAge: ONE_WEEK_MS,
  },
});

export const sessionAdapter: AuthAdapter = {
  async verify(req: Request) {
    if (!req.session.user || !req.session.issuedAt) return null;
    const session: AppSession = {
      user: req.session.user,
      issuedAt: req.session.issuedAt,
      expiresAt: req.session.issuedAt + ONE_WEEK_MS,
    };
    return session;
  },
  async issue(user: User, _res: Response) {
    return { };
  },
  async revoke(req: Request, _res: Response) {
    await new Promise<void>((resolve) => {
      req.session.destroy(() => resolve());
    });
  },
  async refresh() {
    throw new Error('session refresh not supported — sessions auto-refresh per request');
  },
};
```

Required `package.json`: `"express-session": "^1.18.1"`, dev `"@types/express-session": "^1.18.1"`.

`auth.controller.ts` must call `req.session.user = user; req.session.issuedAt = Date.now();` before/after `authAdapter.issue` for Session — see the per-adapter overlay notes at the end of this file.

`src/app.ts` mounts the middleware:
```ts
import { sessionMiddleware } from './shared/auth/adapters/session.adapter.js';
app.use(sessionMiddleware);
```

`env.ts`: `SESSION_SECRET: z.string().min(16)`.

### OAuth stub — `src/shared/auth/adapters/oauth.adapter.ts`

```ts
import type { Request, Response } from 'express';
import type { AuthAdapter, User } from '../types.js';

export const oauthAdapter: AuthAdapter = {
  async verify(req: Request) {
    // TODO: read the bearer token issued by your OAuth provider,
    // call the provider's /userinfo endpoint (or verify the JWT),
    // and return a Session.
    void req;
    return null;
  },
  async issue(_user: User, _res: Response) {
    // OAuth issues tokens via the provider, not us. This method is a no-op
    // for the redirect-based flow — the provider hands the user back with
    // a code, you exchange it for a token, and set it client-side.
    return {};
  },
  async revoke(_req: Request, _res: Response) {
    // TODO: call the provider's revocation endpoint and clear local state.
  },
  async refresh(_req: Request, _res: Response) {
    // TODO: exchange the refresh token at the provider's /token endpoint.
    throw new Error('OAuth refresh not implemented — plug in your provider');
  },
};
```

The OAuth stub does **not** implement a real flow. The user is expected to plug in a provider (Auth0, Keycloak, GitHub, etc.) by filling in the TODOs. The skill generates the shape so the layer wiring works on day one.

---

## Frontend layer files (always the same)

### `src/shared/auth/AuthContext.tsx`

```tsx
import { createContext } from 'react';
import type { User, Credentials } from './types.js';

export type AuthContextValue = {
  user: User | null;
  loading: boolean;
  login(creds: Credentials): Promise<void>;
  logout(): Promise<void>;
  refresh(): Promise<void>;
};

export const AuthContext = createContext<AuthContextValue | null>(null);
```

### `src/shared/auth/AuthProvider.tsx`

```tsx
import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react';
import { AuthContext } from './AuthContext.js';
import { authAdapter } from './adapters/index.js';
import type { User, Credentials } from './types.js';

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    authAdapter
      .bootstrap()
      .then((u) => {
        if (!cancelled) setUser(u);
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  const login = useCallback(async (creds: Credentials) => {
    const u = await authAdapter.login(creds);
    setUser(u);
  }, []);

  const logout = useCallback(async () => {
    await authAdapter.logout();
    setUser(null);
  }, []);

  const refresh = useCallback(async () => {
    const u = await authAdapter.refresh();
    setUser(u);
  }, []);

  const value = useMemo(
    () => ({ user, loading, login, logout, refresh }),
    [user, loading, login, logout, refresh],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}
```

### `src/shared/auth/useAuth.ts`

```ts
import { useContext } from 'react';
import { AuthContext, type AuthContextValue } from './AuthContext.js';

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used inside <AuthProvider>');
  return ctx;
}
```

### `src/shared/auth/ProtectedRoute.tsx`

```tsx
import type { ReactNode } from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { useAuth } from './useAuth.js';

export function ProtectedRoute({ children }: { children: ReactNode }) {
  const { user, loading } = useAuth();
  const location = useLocation();

  if (loading) return <div>Loading…</div>;
  if (!user) {
    return <Navigate to="/login" replace state={{ from: location.pathname }} />;
  }
  return <>{children}</>;
}
```

### `src/shared/auth/adapters/index.ts` (frontend)

```ts
// Swap this line to change auth method:
//   export { jwtAdapter as authAdapter } from './jwt.adapter.js';
//   export { sessionAdapter as authAdapter } from './session.adapter.js';
//   export { oauthAdapter as authAdapter } from './oauth.adapter.js';
export { jwtAdapter as authAdapter } from './jwt.adapter.js';
```

---

## Frontend module — `src/modules/auth/`

Three pages. Same shape regardless of adapter.

### `src/modules/auth/index.ts`

```ts
import { lazy } from 'react';

export const LoginModule = lazy(() => import('./LoginPage'));
export const RegisterModule = lazy(() => import('./RegisterPage'));
export const ForgotPasswordModule = lazy(() => import('./ForgotPasswordPage'));
```

### `src/modules/auth/LoginPage.tsx`

```tsx
import { useState, type FormEvent } from 'react';
import { Link, useNavigate, useLocation } from 'react-router-dom';
import { useAuth } from '../../shared/auth/useAuth.js';
import { Button } from '../../shared/components/Button.js';

export default function LoginPage() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setSubmitting(true);
    setError(null);
    try {
      await login({ email, password });
      const from = (location.state as { from?: string } | null)?.from ?? '/';
      navigate(from, { replace: true });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Login failed');
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <form onSubmit={onSubmit}>
      <h1>Sign in</h1>
      <label>
        Email
        <input
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          required
          autoComplete="email"
        />
      </label>
      <label>
        Password
        <input
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          required
          autoComplete="current-password"
        />
      </label>
      {error && <p role="alert">{error}</p>}
      <Button type="submit" disabled={submitting}>
        {submitting ? 'Signing in…' : 'Sign in'}
      </Button>
      <p>
        No account? <Link to="/register">Create one</Link> ·{' '}
        <Link to="/forgot">Forgot password</Link>
      </p>
    </form>
  );
}
```

### `src/modules/auth/RegisterPage.tsx` and `ForgotPasswordPage.tsx`

Same shape as `LoginPage.tsx` — local form state, calls the relevant API endpoint (`/auth/register`, `/auth/forgot`) via `src/shared/lib/api.ts`. The skill generates simple working stubs; the user fills in the real flow.

### `tests/modules/auth/LoginPage.test.tsx`

```tsx
import { describe, it, expect, vi } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import LoginPage from '../../../src/modules/auth/LoginPage.js';
import { AuthContext } from '../../../src/shared/auth/AuthContext.js';

describe('LoginPage', () => {
  it('calls login() with the entered credentials', async () => {
    const login = vi.fn().mockResolvedValue(undefined);
    render(
      <MemoryRouter>
        <AuthContext.Provider
          value={{
            user: null,
            loading: false,
            login,
            logout: vi.fn(),
            refresh: vi.fn(),
          }}
        >
          <LoginPage />
        </AuthContext.Provider>
      </MemoryRouter>,
    );

    await userEvent.type(screen.getByLabelText(/email/i), 'demo@example.com');
    await userEvent.type(screen.getByLabelText(/password/i), 'demo');
    await userEvent.click(screen.getByRole('button', { name: /sign in/i }));

    await waitFor(() => {
      expect(login).toHaveBeenCalledWith({ email: 'demo@example.com', password: 'demo' });
    });
  });
});
```

`package.json` needs `@testing-library/user-event` in devDeps when auth is on.

---

## Frontend adapters (pick one)

### JWT — `src/shared/auth/adapters/jwt.adapter.ts`

```ts
import { api } from '../../lib/api.js';
import type { AuthAdapter, Credentials, User } from '../types.js';

let accessToken: string | null = null;

export function getAccessToken(): string | null {
  return accessToken;
}

export const jwtAdapter: AuthAdapter = {
  async bootstrap() {
    try {
      const { accessToken: token } = await api.post<{ accessToken: string }>('/auth/refresh', {});
      accessToken = token;
      const { user } = await api.get<{ user: User }>('/auth/me');
      return user;
    } catch {
      return null;
    }
  },
  async login(creds: Credentials) {
    const { user, accessToken: token } = await api.post<{ user: User; accessToken: string }>(
      '/auth/login',
      creds,
    );
    accessToken = token;
    return user;
  },
  async logout() {
    await api.post('/auth/logout', {});
    accessToken = null;
  },
  async refresh() {
    const { accessToken: token } = await api.post<{ accessToken: string }>('/auth/refresh', {});
    accessToken = token;
    const { user } = await api.get<{ user: User }>('/auth/me');
    return user;
  },
};
```

When JWT is the chosen adapter, also update `src/shared/lib/api.ts` to attach the access token to outgoing requests:
```ts
import { getAccessToken } from '../auth/adapters/jwt.adapter.js';
// in request(): headers: { ..., Authorization: getAccessToken() ? `Bearer ${getAccessToken()}` : '' }
```

### Session — `src/shared/auth/adapters/session.adapter.ts`

```ts
import { api } from '../../lib/api.js';
import type { AuthAdapter, Credentials, User } from '../types.js';

export const sessionAdapter: AuthAdapter = {
  async bootstrap() {
    try {
      const { user } = await api.get<{ user: User }>('/auth/me');
      return user;
    } catch {
      return null;
    }
  },
  async login(creds: Credentials) {
    const { user } = await api.post<{ user: User }>('/auth/login', creds);
    return user;
  },
  async logout() {
    await api.post('/auth/logout', {});
  },
  async refresh() {
    // Session cookies are renewed server-side on every request — re-fetch /me.
    const { user } = await api.get<{ user: User }>('/auth/me');
    return user;
  },
};
```

`src/shared/lib/api.ts` already sets `credentials: 'include'`, so the cookie travels automatically. No changes needed.

### OAuth stub — `src/shared/auth/adapters/oauth.adapter.ts`

```ts
import type { AuthAdapter, Credentials, User } from '../types.js';

export const oauthAdapter: AuthAdapter = {
  async bootstrap() {
    // TODO: check for a token in URL hash / localStorage / cookie set by your provider's redirect.
    return null;
  },
  async login(_creds: Credentials): Promise<User> {
    // OAuth typically doesn't use credentials directly — redirect to the provider instead.
    window.location.href = '/oauth/login';
    throw new Error('redirecting'); // unreachable; calm TS
  },
  async logout() {
    window.location.href = '/oauth/logout';
  },
  async refresh(): Promise<User> {
    // TODO: implement token refresh against your provider.
    throw new Error('OAuth refresh not implemented — plug in your provider');
  },
};
```

---

## Wiring summary

When auth = yes, the skill performs these additional steps:

1. **Backend** — generate `src/modules/auth/*`, `src/shared/auth/{requireAuth.ts, types.ts, adapters/index.ts, adapters/<chosen>.adapter.ts}`, the adapter-specific `package.json` deps, the adapter-specific env keys, and the adapter-specific `src/app.ts` middleware mounts.
2. **Frontend** — generate `src/modules/auth/{LoginPage,RegisterPage,ForgotPasswordPage}.tsx + index.ts`, `src/shared/auth/{AuthContext.tsx, AuthProvider.tsx, useAuth.ts, ProtectedRoute.tsx, types.ts, adapters/index.ts, adapters/<chosen>.adapter.ts}`, the adapter-specific tweaks to `src/shared/lib/api.ts`, and the auth-aware route map in `src/routes/index.tsx` (per [frontend-modules.md](frontend-modules.md)).
3. **Fullstack** — both of the above. Plus `packages/shared/src/index.ts` adds the `User` type so backend and frontend agree on the shape.

The skill writes **exactly one** adapter file per side. Never two, never zero (when auth=yes).

---

## How to swap auth methods later

1. Write the new adapter at `src/shared/auth/adapters/<new>.adapter.ts` (use one of the three above as a starting point).
2. Update `src/shared/auth/adapters/index.ts` to re-export the new one as `authAdapter`.
3. Update `package.json` deps (add the new method's libs, remove the old method's libs).
4. Update `src/app.ts` middleware mounts (cookie-parser ↔ express-session ↔ nothing).
5. Update `src/config/env.ts` schema (`JWT_SECRET` ↔ `SESSION_SECRET` ↔ provider config).

**Modules (`src/modules/*`) are not touched.** That's the whole point of the layer.
