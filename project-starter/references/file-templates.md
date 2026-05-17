# file-templates

Every file body the skill writes. Placeholders: `{{name}}` (project name, kebab-case), `{{framework}}` (Express/Vite/etc.), `{{port}}` (3000 backend, 5173 frontend). Per-type and per-architecture variations are noted inline.

Files that only appear under specific conditions (DB, auth, OpenAPI, architecture style) live in their dedicated reference files:
- DB-conditional → [database-recipes.md](database-recipes.md)
- Auth-conditional → [auth-layer.md](auth-layer.md)
- Architecture-specific module shape → [architecture-styles.md](architecture-styles.md)
- Frontend module/layout files → [frontend-modules.md](frontend-modules.md)
- Dockerfiles + compose files → [docker-recipes.md](docker-recipes.md)
- CLAUDE.md + `.claude/settings.json` → [claude-wire.md](claude-wire.md)

---

## Universal

### `.editorconfig`

```
root = true

[*]
indent_style = space
indent_size = 2
end_of_line = lf
charset = utf-8
trim_trailing_whitespace = true
insert_final_newline = true

[*.md]
trim_trailing_whitespace = false
```

### `.gitignore`

```
node_modules/
dist/
build/
coverage/
.env
.env.local
.DS_Store

# Yarn 4 — commit the binary, ignore everything else
.yarn/*
!.yarn/releases
!.yarn/plugins
!.yarn/sdks
!.yarn/versions
.pnp.*
.yarn/install-state.gz
.yarn/cache
```

For **library**, add:
```
dist/
*.tgz
```

For **monorepo / fullstack**, add:
```
apps/*/dist/
packages/*/dist/
```

### `.prettierrc`

```json
{
  "semi": true,
  "singleQuote": true,
  "trailingComma": "all",
  "printWidth": 100,
  "tabWidth": 2
}
```

### `.eslintrc.cjs`

```javascript
module.exports = {
  root: true,
  parser: '@typescript-eslint/parser',
  parserOptions: { ecmaVersion: 2022, sourceType: 'module' },
  plugins: ['@typescript-eslint'],
  extends: [
    'eslint:recommended',
    'plugin:@typescript-eslint/recommended',
    'prettier',
  ],
  ignorePatterns: ['dist', 'node_modules', '.yarn'],
  rules: {
    '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
  },
};
```

For **frontend**, add to `extends`: `'plugin:react-hooks/recommended'`. Add `plugins: ['react-refresh']` and the rule `'react-refresh/only-export-components': 'warn'`.

### `.yarnrc.yml`

```yaml
nodeLinker: node-modules
enableGlobalCache: true
yarnPath: .yarn/releases/yarn-4.5.0.cjs
```

For **fullstack / monorepo**, append:
```yaml
nmHoistingLimits: workspaces
```

### `.dockerignore`

```
node_modules
dist
build
coverage
.git
.github
.env
.env.local
.yarn/cache
.yarn/install-state.gz
*.log
.DS_Store
```

### `.env.example`

Backend:
```
PORT=3000
LOG_LEVEL=info
# Database (only present if DB chosen)
DB_HOST=db
DB_PORT=3306
DB_USER=root
DB_PASSWORD=change-me
DB_NAME={{name}}
# Auth (only present if auth=yes)
JWT_SECRET=change-me-in-production
SESSION_SECRET=change-me-in-production
```

Frontend:
```
VITE_API_URL=http://localhost:3000
```

Fullstack: union of the two with the frontend keys prefixed `VITE_`.

CLI / library: empty or only what the CLI needs.

### `README.md` (per type, ~30 lines)

```markdown
# {{name}}

{{type-one-liner}}

## Stack

Node 20 · Yarn 4 · TypeScript (ESM) · {{framework}}{{db-suffix}}{{auth-suffix}}

## Quick start

```
docker compose up
```

Then visit {{dev-url}}.

## Commands

All commands run inside Docker:

| Command                                | What it does                |
| -------------------------------------- | --------------------------- |
| `docker compose up`                    | Start the dev server        |
| `docker compose run --rm app yarn lint`| Lint                        |
| `docker compose run --rm app yarn test`| Run Vitest                  |
| `docker compose run --rm app yarn build`| Build for production       |

See `CLAUDE.md` for conventions.

## License

Not set. Add a `LICENSE` file when you're ready to publish.
```

Per-type fill-ins:
- Backend API → `{{type-one-liner}}` = "HTTP service.", `{{framework}}` = "Express", `{{dev-url}}` = "http://localhost:3000/health"
- Frontend → "Single-page app.", "Vite + React", "http://localhost:5173"
- Fullstack → "API + web app, shipped together.", "Express + Vite + React", "API at :3000, web at :5173"
- CLI → "Command-line tool.", "Node + Commander", "—" (no dev URL)
- Library → "Publishable TypeScript library.", "TypeScript", "—"
- Monorepo → "Yarn 4 workspaces.", "varied per package", "—"

---

## Backend API

### `package.json`

```json
{
  "name": "{{name}}",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "packageManager": "yarn@4.5.0",
  "engines": { "node": ">=20" },
  "scripts": {
    "dev": "tsx watch src/index.ts",
    "build": "tsc -p tsconfig.json",
    "start": "node dist/index.js",
    "test": "vitest run",
    "test:watch": "vitest",
    "lint": "eslint .",
    "format": "prettier --write ."
  },
  "dependencies": {
    "express": "^4.21.0",
    "pino": "^9.5.0",
    "pino-http": "^10.3.0",
    "zod": "^3.23.8"
  },
  "devDependencies": {
    "@types/express": "^5.0.0",
    "@types/node": "^20.17.0",
    "@types/supertest": "^6.0.2",
    "@typescript-eslint/eslint-plugin": "^8.18.0",
    "@typescript-eslint/parser": "^8.18.0",
    "eslint": "^8.57.1",
    "eslint-config-prettier": "^9.1.0",
    "prettier": "^3.4.2",
    "supertest": "^7.0.0",
    "tsx": "^4.19.2",
    "typescript": "^5.7.0",
    "vitest": "^2.1.8"
  }
}
```

If a DB is selected, [database-recipes.md](database-recipes.md) adds the driver dep.
If API docs = yes, add `"swagger-ui-express": "^5.0.1"` and `"@types/swagger-ui-express": "^4.1.7"` to dev deps; add `"yaml": "^2.6.1"` to deps for loading `openapi.yaml`.
If auth = yes, [auth-layer.md](auth-layer.md) adds adapter-specific deps (jsonwebtoken / express-session / etc.).

### `tsconfig.json`

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "resolveJsonModule": true,
    "declaration": false,
    "sourceMap": true,
    "forceConsistentCasingInFileNames": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist", "tests"]
}
```

### `vitest.config.ts`

```ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'node',
    include: ['tests/**/*.test.ts'],
  },
});
```

### `src/index.ts`

```ts
import { createApp } from './app.js';
import { env } from './config/env.js';
import { logger } from './shared/middleware/logger.js';

const app = createApp();
app.listen(env.PORT, () => {
  logger.info({ port: env.PORT }, 'server listening');
});
```

### `src/app.ts` (modular monolith default)

```ts
import express from 'express';
import pinoHttp from 'pino-http';
import { errorHandler } from './shared/middleware/error.js';
import { logger } from './shared/middleware/logger.js';
import healthModule from './modules/health/index.js';
// {{ if auth }}
// import authModule from './modules/auth/index.js';
// {{ /if }}

export function createApp() {
  const app = express();
  app.use(pinoHttp({ logger }));
  app.use(express.json());

  const modules = [healthModule /* {{ if auth }}, authModule {{ /if }} */];
  for (const mod of modules) {
    app.use(mod.mountPath, mod.router);
  }

  app.use(errorHandler);
  return app;
}
```

(Layered / Clean / Hexagonal variants of `app.ts` live in [architecture-styles.md](architecture-styles.md).)

### `src/config/env.ts`

```ts
import { z } from 'zod';

const schema = z.object({
  PORT: z.coerce.number().int().positive().default(3000),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),
  // {{ if db }}
  // DB_HOST: z.string(),
  // DB_PORT: z.coerce.number().int().positive().default(3306),
  // DB_USER: z.string(),
  // DB_PASSWORD: z.string(),
  // DB_NAME: z.string(),
  // {{ /if }}
  // {{ if auth=jwt }}
  // JWT_SECRET: z.string().min(16),
  // {{ /if }}
  // {{ if auth=session }}
  // SESSION_SECRET: z.string().min(16),
  // {{ /if }}
});

const parsed = schema.safeParse(process.env);
if (!parsed.success) {
  console.error('Invalid env:', parsed.error.flatten().fieldErrors);
  process.exit(1);
}

export const env = parsed.data;
```

The `{{ if }}` markers are template directives — the skill resolves them at scaffold time, producing the final file without the markers.

### `src/shared/middleware/logger.ts`

```ts
import pino from 'pino';
import { env } from '../../config/env.js';

export const logger = pino({ level: env.LOG_LEVEL });
```

### `src/shared/middleware/error.ts`

```ts
import type { Request, Response, NextFunction } from 'express';
import { logger } from './logger.js';

export function errorHandler(
  err: Error,
  _req: Request,
  res: Response,
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  _next: NextFunction,
): void {
  logger.error({ err }, 'unhandled error');
  res.status(500).json({ error: { code: 'INTERNAL', message: 'Internal server error' } });
}
```

### `src/modules/health/index.ts`

```ts
import { healthRouter } from './health.routes.js';

export default {
  mountPath: '/health',
  router: healthRouter,
};
```

### `src/modules/health/health.routes.ts`

```ts
import { Router } from 'express';
import { healthController } from './health.controller.js';

export const healthRouter = Router();
healthRouter.get('/', healthController.get);
```

### `src/modules/health/health.controller.ts`

```ts
import type { Request, Response } from 'express';
import { healthService } from './health.service.js';
import { healthResponseSchema } from './health.schema.js';

export const healthController = {
  get(_req: Request, res: Response): void {
    const result = healthService.check();
    res.status(200).json(healthResponseSchema.parse(result));
  },
};
```

### `src/modules/health/health.service.ts`

```ts
import type { HealthResponse } from './health.schema.js';

export const healthService = {
  check(): HealthResponse {
    return { status: 'ok' };
  },
};
```

### `src/modules/health/health.schema.ts`

```ts
import { z } from 'zod';

export const healthResponseSchema = z.object({
  status: z.literal('ok'),
});

export type HealthResponse = z.infer<typeof healthResponseSchema>;
```

### `tests/modules/health.test.ts`

```ts
import { describe, it, expect } from 'vitest';
import request from 'supertest';
import { createApp } from '../../src/app.js';

describe('GET /health', () => {
  it('returns {status:"ok"}', async () => {
    const app = createApp();
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ status: 'ok' });
  });
});
```

### `.github/workflows/ci.yml`

```yaml
# All local development runs through `docker compose run --rm app …`.
# These bare yarn commands are CI-only — see CLAUDE.md.
name: ci
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
      - run: corepack enable
      - run: yarn install --immutable --immutable-cache
      - run: yarn lint
      - run: yarn test
      - run: yarn build
```

### `openapi.yaml` (only if API docs = yes)

```yaml
openapi: 3.1.0
info:
  title: {{name}}
  version: 0.1.0
paths:
  /health:
    get:
      summary: Liveness probe
      responses:
        '200':
          description: Service is up
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Health'
components:
  schemas:
    Health:
      type: object
      required: [status]
      properties:
        status:
          type: string
          enum: [ok]
    Error:
      type: object
      required: [error]
      properties:
        error:
          type: object
          required: [code, message]
          properties:
            code: { type: string }
            message: { type: string }
```

When `openapi.yaml` is present, `src/app.ts` also wires `/docs`:

```ts
import swaggerUi from 'swagger-ui-express';
import { readFileSync } from 'node:fs';
import { parse as parseYaml } from 'yaml';

const openapiDoc = parseYaml(readFileSync(new URL('../openapi.yaml', import.meta.url), 'utf8'));
app.use('/docs', swaggerUi.serve, swaggerUi.setup(openapiDoc));
```

---

## CLI / job

### `package.json`

```json
{
  "name": "{{name}}",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "packageManager": "yarn@4.5.0",
  "engines": { "node": ">=20" },
  "bin": {
    "{{name}}": "dist/bin/cli.js"
  },
  "scripts": {
    "dev": "tsx bin/cli.ts",
    "build": "tsc -p tsconfig.json",
    "start": "node dist/bin/cli.js",
    "test": "vitest run",
    "lint": "eslint .",
    "format": "prettier --write ."
  },
  "dependencies": {
    "commander": "^12.1.0"
  },
  "devDependencies": {
    "@types/node": "^20.17.0",
    "@typescript-eslint/eslint-plugin": "^8.18.0",
    "@typescript-eslint/parser": "^8.18.0",
    "eslint": "^8.57.1",
    "eslint-config-prettier": "^9.1.0",
    "prettier": "^3.4.2",
    "tsx": "^4.19.2",
    "typescript": "^5.7.0",
    "vitest": "^2.1.8"
  }
}
```

### `tsconfig.json`

Same as backend, but `"include": ["src/**/*", "bin/**/*"]`.

### `bin/cli.ts`

```ts
#!/usr/bin/env node
import { main } from '../src/index.js';

main(process.argv.slice(2)).catch((err) => {
  console.error(err);
  process.exit(1);
});
```

### `src/index.ts`

```ts
import { Command } from 'commander';
import { hello } from './commands/hello.js';

export async function main(argv: string[]): Promise<void> {
  const program = new Command();
  program.name('{{name}}').description('{{name}} CLI').version('0.1.0');

  program
    .command('hello')
    .description('Say hello')
    .argument('<name>', 'who to greet')
    .action((name: string) => {
      console.log(hello(name));
    });

  await program.parseAsync(argv, { from: 'user' });
}
```

### `src/commands/hello.ts`

```ts
export function hello(name: string): string {
  return `Hello, ${name}!`;
}
```

### `tests/commands/hello.test.ts`

```ts
import { describe, it, expect } from 'vitest';
import { hello } from '../../src/commands/hello.js';

describe('hello', () => {
  it('greets by name', () => {
    expect(hello('world')).toBe('Hello, world!');
  });
});
```

### `vitest.config.ts`

Identical to backend.

### `.github/workflows/ci.yml`

Identical to backend's, minus the `yarn build` step on the test job — CLIs may not need a build artifact in CI. Actually keep it: declaration of intent that the build succeeds. Same file.

---

## Frontend React (overlays)

Vite produces a baseline; we overlay the files below. Anything Vite generated and we don't list is preserved as-is.

### `package.json` (overlay — merge with Vite's output)

The skill reads Vite's generated `package.json`, then **adds/overrides** these fields:

```jsonc
{
  "type": "module",
  "private": true,
  "packageManager": "yarn@4.5.0",
  "engines": { "node": ">=20" },
  "scripts": {
    "dev": "vite",
    "build": "tsc -b && vite build",
    "preview": "vite preview --host",
    "test": "vitest run",
    "test:watch": "vitest",
    "lint": "eslint .",
    "format": "prettier --write ."
  },
  "devDependencies": {
    "@testing-library/jest-dom": "^6.6.3",
    "@testing-library/react": "^16.1.0",
    "@types/node": "^20.17.0",
    "@vitest/coverage-v8": "^2.1.8",
    "@vitejs/plugin-react": "^4.3.4",
    "eslint-config-prettier": "^9.1.0",
    "jsdom": "^25.0.1",
    "prettier": "^3.4.2",
    "react-router-dom": "^7.1.0",
    "vitest": "^2.1.8"
  }
}
```

(Vite already includes `react`, `react-dom`, `typescript`, `vite`, `@vitejs/plugin-react`, eslint and its plugins.)

### `tsconfig.json` (replace Vite's)

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "useDefineForClassFields": true,
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "skipLibCheck": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "types": ["vitest/globals", "@testing-library/jest-dom"]
  },
  "include": ["src", "tests"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
```

### `vite.config.ts` (replace Vite's)

```ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: { host: true, port: 5173 },
  test: {
    environment: 'jsdom',
    setupFiles: ['./tests/setup.ts'],
    globals: true,
    include: ['tests/**/*.test.{ts,tsx}'],
  },
});
```

### `tests/setup.ts`

```ts
import '@testing-library/jest-dom';
```

### `src/main.tsx`

Keep Vite's. It renders `<App />` into `#root`.

### `src/App.tsx` (replace Vite's)

```tsx
import { BrowserRouter } from 'react-router-dom';
import { AppRoutes } from './routes/index.js';
// {{ if auth }}
// import { AuthProvider } from './shared/auth/AuthProvider.js';
// {{ /if }}

export default function App() {
  return (
    <BrowserRouter>
      {/* {{ if auth }}<AuthProvider>{{ /if }} */}
      <AppRoutes />
      {/* {{ if auth }}</AuthProvider>{{ /if }} */}
    </BrowserRouter>
  );
}
```

The route map, layouts, modules, and shared files for frontend all live in [frontend-modules.md](frontend-modules.md).

### `.github/workflows/ci.yml`

Same shape as backend, but jobs are `lint` and `test` (no `yarn build` to keep CI fast — Vite builds take seconds locally but minutes on cold CI runners).

---

## Fullstack — root files

### Root `package.json`

```json
{
  "name": "{{name}}",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "packageManager": "yarn@4.5.0",
  "workspaces": ["apps/*", "packages/*"],
  "scripts": {
    "build":  "yarn workspaces foreach -A run build",
    "lint":   "yarn workspaces foreach -A run lint",
    "test":   "yarn workspaces foreach -A run test",
    "format": "prettier --write \"apps/**/*.{ts,tsx,js,json,md}\" \"packages/**/*.{ts,tsx,js,json,md}\""
  },
  "devDependencies": {
    "prettier": "^3.4.2",
    "typescript": "^5.7.0"
  }
}
```

### Root `tsconfig.base.json`

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationMap": true,
    "composite": true,
    "forceConsistentCasingInFileNames": true
  }
}
```

`apps/api/tsconfig.json` and `packages/shared/tsconfig.json` extend this. `apps/web/tsconfig.json` overrides `module: "ESNext"` and `moduleResolution: "bundler"` (frontend uses bundler resolution).

### `packages/shared/package.json`

```json
{
  "name": "@{{name}}/shared",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "main": "./src/index.ts",
  "exports": { ".": "./src/index.ts" },
  "scripts": {
    "build": "tsc -b",
    "lint": "eslint .",
    "test": "vitest run"
  },
  "devDependencies": {
    "typescript": "^5.7.0",
    "vitest": "^2.1.8"
  }
}
```

### `packages/shared/src/index.ts`

```ts
export type HealthResponse = { status: 'ok' };
```

The API and the web app both import this — single source of truth for the contract.

### Root `Dockerfile.tools`

Lives in [docker-recipes.md](docker-recipes.md).

---

## Monorepo — root files

Root `package.json`, `tsconfig.base.json`, `.yarnrc.yml`, etc. are identical to fullstack's. The starter package under `packages/{{name}}-core/` uses the **Library** template.

---

## Library

### `package.json`

```json
{
  "name": "{{name}}",
  "version": "0.1.0",
  "description": "",
  "type": "module",
  "packageManager": "yarn@4.5.0",
  "engines": { "node": ">=20" },
  "main": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": {
      "types": "./dist/index.d.ts",
      "import": "./dist/index.js"
    }
  },
  "files": ["dist", "README.md", "LICENSE"],
  "scripts": {
    "build": "tsc -p tsconfig.json",
    "test": "vitest run",
    "lint": "eslint .",
    "format": "prettier --write .",
    "prepublishOnly": "yarn build && yarn test"
  },
  "publishConfig": {
    "access": "public"
  },
  "devDependencies": {
    "@types/node": "^20.17.0",
    "@typescript-eslint/eslint-plugin": "^8.18.0",
    "@typescript-eslint/parser": "^8.18.0",
    "eslint": "^8.57.1",
    "eslint-config-prettier": "^9.1.0",
    "prettier": "^3.4.2",
    "typescript": "^5.7.0",
    "vitest": "^2.1.8"
  }
}
```

If publish target = "Private registry", swap `publishConfig` for:
```json
"publishConfig": { "registry": "https://registry.example.com/" }
```

If publish target = "Local only", remove `publishConfig` entirely and set `"private": true`.

### `tsconfig.json`

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "declaration": true,
    "declarationMap": true,
    "composite": true,
    "sourceMap": true,
    "forceConsistentCasingInFileNames": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist", "tests"]
}
```

### `src/index.ts`

```ts
export { hello } from './lib/hello.js';
```

### `src/lib/hello.ts`

```ts
export function hello(name: string): string {
  return `Hello, ${name}!`;
}
```

### `tests/index.test.ts`

```ts
import { describe, it, expect } from 'vitest';
import { hello } from '../src/index.js';

describe('hello', () => {
  it('greets by name', () => {
    expect(hello('world')).toBe('Hello, world!');
  });
});
```

### `.npmignore`

```
src/
tests/
tsconfig.json
.eslintrc.cjs
.prettierrc
.editorconfig
.yarnrc.yml
.yarn/
Dockerfile
docker-compose.yml
vitest.config.ts
```

### `vitest.config.ts`

Identical to backend's.

### `.github/workflows/release.yml` (only if publish target ≠ "Local only")

```yaml
name: release
on:
  push:
    tags: ['v*']
jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          registry-url: https://registry.npmjs.org
      - run: corepack enable
      - run: yarn install --immutable
      - run: yarn build
      - run: yarn test
      - run: yarn npm publish
        env:
          NPM_AUTH_TOKEN: ${{ secrets.NPM_AUTH_TOKEN }}
```
