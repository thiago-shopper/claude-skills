# architecture-styles

Four backend architectures. The module boundary (`src/modules/<name>/`) is the same across all four; what changes is the file set **inside** each module. The composition root (`src/app.ts`) also varies.

Health module is shown for each. Auth modules follow the same pattern — see [auth-layer.md](auth-layer.md) for the auth-specific files in each style.

---

## 1. Modular monolith (default)

Each module owns the full vertical slice: HTTP, business logic, schema, optional persistence. The shared kernel (`src/shared/`) holds infrastructure only.

```
src/
├── modules/
│   └── <name>/
│       ├── <name>.routes.ts        # Express router
│       ├── <name>.controller.ts    # request handlers
│       ├── <name>.service.ts       # business logic
│       ├── <name>.repository.ts    # DB access (only if module needs persistence)
│       ├── <name>.schema.ts        # zod schemas (request, response, domain)
│       └── index.ts                # { router, mountPath }
├── shared/
│   ├── middleware/
│   ├── db/
│   ├── lib/
│   └── types/
├── config/env.ts
├── app.ts
└── index.ts
```

The health module shape is in [file-templates.md#srcmoduleshealthhealthroutests](file-templates.md). The `src/app.ts` body that iterates `modules/*/index.ts` is also in file-templates.md.

**Rule of thumb:** when in doubt, pick this. It's the default for a reason.

---

## 2. Layered

Flat split — all routes in one folder, all services in another, all repositories in another.

```
src/
├── routes/
│   ├── health.routes.ts
│   └── index.ts                    # mounts every route file
├── controllers/
│   └── health.controller.ts
├── services/
│   └── health.service.ts
├── repositories/                   # if DB chosen
│   └── (empty for hello-world)
├── schemas/
│   └── health.schema.ts
├── shared/
│   ├── middleware/
│   ├── db/
│   ├── lib/
│   └── types/
├── config/env.ts
├── app.ts
└── index.ts
```

### `src/app.ts` (layered)

```ts
import express from 'express';
import pinoHttp from 'pino-http';
import { errorHandler } from './shared/middleware/error.js';
import { logger } from './shared/middleware/logger.js';
import { router } from './routes/index.js';

export function createApp() {
  const app = express();
  app.use(pinoHttp({ logger }));
  app.use(express.json());
  app.use(router);
  app.use(errorHandler);
  return app;
}
```

### `src/routes/index.ts`

```ts
import { Router } from 'express';
import { healthRouter } from './health.routes.js';

export const router = Router();
router.use('/health', healthRouter);
```

### `src/routes/health.routes.ts`, `controllers/health.controller.ts`, `services/health.service.ts`, `schemas/health.schema.ts`

Same bodies as the modular variant — they're just moved to layer folders instead of being grouped under `modules/health/`.

**When to pick this:** tiny projects with ≤ 5 routes that you don't expect to grow. It's the easiest to understand on day one but couples features to layer files as the project grows.

---

## 3. Clean Architecture

Per-module, four concentric layers. Dependencies point inward only: `infra → interfaces → usecases → entities`.

```
src/
├── modules/
│   └── <name>/
│       ├── entities/               # plain data + invariants
│       │   └── <name>.entity.ts
│       ├── usecases/               # application-specific business rules
│       │   └── <name>.usecase.ts
│       ├── interfaces/             # ports + DTOs that cross the boundary
│       │   ├── <name>.controller.ts
│       │   ├── <name>.presenter.ts
│       │   └── <name>.repository.interface.ts
│       ├── infra/                  # frameworks + drivers
│       │   ├── <name>.routes.ts    # Express wiring
│       │   └── <name>.repository.ts # DB impl (if module needs persistence)
│       └── index.ts                # composition root for the module
├── shared/
│   ├── middleware/
│   ├── db/
│   ├── lib/
│   └── types/
├── config/env.ts
├── app.ts
└── index.ts
```

### Health module — `src/modules/health/`

**`entities/health.entity.ts`**
```ts
export class HealthStatus {
  constructor(public readonly status: 'ok') {}
}
```

**`usecases/health.usecase.ts`**
```ts
import { HealthStatus } from '../entities/health.entity.js';

export class CheckHealthUseCase {
  execute(): HealthStatus {
    return new HealthStatus('ok');
  }
}
```

**`interfaces/health.controller.ts`**
```ts
import type { Request, Response } from 'express';
import type { CheckHealthUseCase } from '../usecases/health.usecase.js';

export class HealthController {
  constructor(private readonly useCase: CheckHealthUseCase) {}
  get = (_req: Request, res: Response): void => {
    const result = this.useCase.execute();
    res.status(200).json({ status: result.status });
  };
}
```

**`infra/health.routes.ts`**
```ts
import { Router } from 'express';
import { CheckHealthUseCase } from '../usecases/health.usecase.js';
import { HealthController } from '../interfaces/health.controller.js';

export function makeHealthRouter(): Router {
  const useCase = new CheckHealthUseCase();
  const controller = new HealthController(useCase);
  const router = Router();
  router.get('/', controller.get);
  return router;
}
```

**`index.ts`**
```ts
import { makeHealthRouter } from './infra/health.routes.js';

export default {
  mountPath: '/health',
  router: makeHealthRouter(),
};
```

### `src/app.ts` (clean)

Same as the modular monolith — iterates `modules/*/index.ts` and mounts each one's router. The architectural strictness is *inside* each module; the composition root is identical.

**When to pick this:** medium-to-large teams already practicing Clean Architecture. Worth the ceremony when business rules genuinely need protection from framework churn. Overkill for a hello-world or a thin CRUD service.

---

## 4. Hexagonal (Ports & Adapters)

Per-module, three groups: domain (pure), ports (interfaces), adapters (concrete impls — HTTP, DB, queue).

```
src/
├── modules/
│   └── <name>/
│       ├── domain/                 # entities + domain services (no framework imports)
│       │   ├── <name>.entity.ts
│       │   └── <name>.service.ts
│       ├── ports/                  # interfaces — what the domain needs from the outside
│       │   ├── <name>.in.port.ts   # driving port (use case interface)
│       │   └── <name>.out.port.ts  # driven port (repository interface, if any)
│       ├── adapters/
│       │   ├── http/
│       │   │   ├── <name>.controller.ts
│       │   │   └── <name>.routes.ts
│       │   └── persistence/        # only if DB chosen
│       │       └── <name>.mysql.adapter.ts
│       └── index.ts                # wires ports to adapters
├── shared/
│   ├── middleware/
│   ├── db/
│   ├── lib/
│   └── types/
├── config/env.ts
├── app.ts
└── index.ts
```

### Health module — `src/modules/health/`

**`domain/health.entity.ts`**
```ts
export type HealthStatus = { readonly status: 'ok' };
```

**`domain/health.service.ts`**
```ts
import type { HealthStatus } from './health.entity.js';

export class HealthService {
  check(): HealthStatus {
    return { status: 'ok' };
  }
}
```

**`ports/health.in.port.ts`**
```ts
import type { HealthStatus } from '../domain/health.entity.js';

export interface CheckHealthPort {
  check(): HealthStatus;
}
```

**`adapters/http/health.controller.ts`**
```ts
import type { Request, Response } from 'express';
import type { CheckHealthPort } from '../../ports/health.in.port.js';

export class HealthController {
  constructor(private readonly port: CheckHealthPort) {}
  get = (_req: Request, res: Response): void => {
    res.status(200).json(this.port.check());
  };
}
```

**`adapters/http/health.routes.ts`**
```ts
import { Router } from 'express';
import type { HealthController } from './health.controller.js';

export function makeHealthRouter(controller: HealthController): Router {
  const router = Router();
  router.get('/', controller.get);
  return router;
}
```

**`index.ts`**
```ts
import { HealthService } from './domain/health.service.js';
import { HealthController } from './adapters/http/health.controller.js';
import { makeHealthRouter } from './adapters/http/health.routes.js';

const service = new HealthService();           // implements CheckHealthPort
const controller = new HealthController(service);
const router = makeHealthRouter(controller);

export default { mountPath: '/health', router };
```

### `src/app.ts` (hexagonal)

Identical to modular — iterates `modules/*/index.ts` and mounts. Wiring lives inside each module's `index.ts`.

**When to pick this:** modules that need to swap infrastructure (DB engine, message broker, HTTP transport) without touching domain code. Good fit for services that talk to multiple downstreams or are part of a polyglot stack.

---

## Cross-style notes

- **Tests** mirror the source folder tree under `tests/`. For modular, tests live at `tests/modules/<name>/<name>.test.ts`. For layered, `tests/routes/<name>.test.ts`. For clean/hexagonal, `tests/modules/<name>/<layer>/<file>.test.ts`.
- **Auth integration** is documented in [auth-layer.md](auth-layer.md). For modular, auth is just another module. For layered, auth is split across `routes/auth.routes.ts` + `controllers/auth.controller.ts` + `services/auth.service.ts`. For clean/hexagonal, the auth module follows the same internal structure as health, with the adapter being the chosen auth method.
- **Switching architectures after scaffold** is possible but manual. The skill picks one style at scaffold time and writes only that style's files. Re-running the skill won't migrate an existing project.
