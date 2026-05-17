# database-recipes

When the user picks a database, three things get added to the scaffold:

1. A driver dependency in `package.json`.
2. A service block in `docker-compose.yml` (plus a `volumes:` entry for the data volume) — slots into the `{{ db-service }}` and `{{ db-volumes }}` placeholders from [docker-recipes.md](docker-recipes.md).
3. A `src/shared/db/client.ts` connection pool.

Plus a few env keys in `.env.example` and a zod schema fragment in `src/config/env.ts`.

Default is **MySQL 8**. Postgres and SQLite variants follow.

---

## MySQL 8 (default)

### `package.json` deps

Add to `dependencies`:
```json
"mysql2": "^3.11.5"
```

### `docker-compose.yml` — `{{ db-service }}` block

```yaml
  db:
    image: mysql:8
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_PASSWORD}
      MYSQL_DATABASE: ${DB_NAME}
    ports:
      - "${DB_PORT:-3306}:3306"
    volumes:
      - dbdata:/var/lib/mysql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "127.0.0.1", "-uroot", "-p${DB_PASSWORD}"]
      interval: 5s
      timeout: 3s
      retries: 12
```

### `docker-compose.yml` — `{{ db-volumes }}` block

```yaml
volumes:
  dbdata:
```

### `docker-compose.yml` — `{{ db-service-depends }}` block

```yaml
    depends_on:
      db:
        condition: service_healthy
```

(For fullstack root compose, use `{{ db-service-depends-on-api }}` with the same block under the `api:` service.)

### `.env.example` additions

```
DB_HOST=db
DB_PORT=3306
DB_USER=root
DB_PASSWORD=change-me
DB_NAME={{name}}
```

### `src/config/env.ts` schema fragment

Add to the zod object:
```ts
DB_HOST: z.string(),
DB_PORT: z.coerce.number().int().positive().default(3306),
DB_USER: z.string(),
DB_PASSWORD: z.string(),
DB_NAME: z.string(),
```

### `src/shared/db/client.ts`

```ts
import { createPool, type Pool } from 'mysql2/promise';
import { env } from '../../config/env.js';

let pool: Pool | null = null;

export function getPool(): Pool {
  if (pool) return pool;
  pool = createPool({
    host: env.DB_HOST,
    port: env.DB_PORT,
    user: env.DB_USER,
    password: env.DB_PASSWORD,
    database: env.DB_NAME,
    waitForConnections: true,
    connectionLimit: 10,
    queueLimit: 0,
  });
  return pool;
}

export async function query<T = unknown>(sql: string, params?: unknown[]): Promise<T[]> {
  const [rows] = await getPool().query(sql, params);
  return rows as T[];
}
```

---

## PostgreSQL 16

### `package.json` deps

Add:
```json
"pg": "^8.13.1"
```

And to `devDependencies`:
```json
"@types/pg": "^8.11.10"
```

### `docker-compose.yml` — `{{ db-service }}` block

```yaml
  db:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: ${DB_NAME}
    ports:
      - "${DB_PORT:-5432}:5432"
    volumes:
      - dbdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER} -d ${DB_NAME}"]
      interval: 5s
      timeout: 3s
      retries: 12
```

### `{{ db-volumes }}` and `{{ db-service-depends }}`

Same shape as MySQL — `dbdata:` volume, `depends_on: { db: { condition: service_healthy } }`.

### `.env.example` additions

```
DB_HOST=db
DB_PORT=5432
DB_USER=postgres
DB_PASSWORD=change-me
DB_NAME={{name}}
```

### `src/config/env.ts` schema fragment

Same as MySQL but with `DB_PORT: z.coerce.number().int().positive().default(5432)`.

### `src/shared/db/client.ts`

```ts
import pg from 'pg';
import { env } from '../../config/env.js';

const { Pool } = pg;

let pool: pg.Pool | null = null;

export function getPool(): pg.Pool {
  if (pool) return pool;
  pool = new Pool({
    host: env.DB_HOST,
    port: env.DB_PORT,
    user: env.DB_USER,
    password: env.DB_PASSWORD,
    database: env.DB_NAME,
    max: 10,
  });
  return pool;
}

export async function query<T extends pg.QueryResultRow = pg.QueryResultRow>(
  sql: string,
  params?: unknown[],
): Promise<T[]> {
  const result = await getPool().query<T>(sql, params);
  return result.rows;
}
```

---

## SQLite

SQLite is file-backed, so there's **no compose service** for it. The data file lives at `./data/db.sqlite` (bind-mounted into the container at `/app/data/db.sqlite`).

### `package.json` deps

Add:
```json
"better-sqlite3": "^11.5.0"
```

And to `devDependencies`:
```json
"@types/better-sqlite3": "^7.6.12"
```

> ⚠️ `better-sqlite3` is a native module. The Alpine base image needs `python3 make g++` to build it. Add to the Dockerfile before `yarn install`:
> ```dockerfile
> RUN apk add --no-cache python3 make g++
> ```

### `docker-compose.yml` — `{{ db-service }}` block

(empty — SQLite has no service)

### `docker-compose.yml` — `{{ db-volumes }}` block

(empty)

### `docker-compose.yml` — `{{ db-service-depends }}` block

(empty)

Also add to the `app` service's `volumes:`:
```yaml
      - ./data:/app/data
```

And create a `data/.gitkeep` file at the repo root so the directory exists when the bind mount is created.

### `.env.example` additions

```
DB_PATH=/app/data/db.sqlite
```

### `src/config/env.ts` schema fragment

```ts
DB_PATH: z.string().default('/app/data/db.sqlite'),
```

### `src/shared/db/client.ts`

```ts
import Database from 'better-sqlite3';
import { env } from '../../config/env.js';

let db: Database.Database | null = null;

export function getDb(): Database.Database {
  if (db) return db;
  db = new Database(env.DB_PATH);
  db.pragma('journal_mode = WAL');
  return db;
}

export function query<T = unknown>(sql: string, params?: unknown[]): T[] {
  return getDb().prepare(sql).all(...(params ?? [])) as T[];
}
```

(SQLite's `better-sqlite3` is synchronous by design — the API doesn't return Promises. Document this in `CLAUDE.md` so callers don't accidentally `await` it.)

---

## None

If the user picks "No database":
- No driver dep added.
- All `{{ db-* }}` placeholders in `docker-compose.yml` resolve to empty strings.
- `src/shared/db/` is **not generated**.
- No DB-related env keys in `.env.example` or `src/config/env.ts`.

---

## Health-check coupling

When a DB is chosen, the `health` module is left intentionally simple — it returns `{status:"ok"}` without checking the DB. Users who want a "ready" probe should add a separate `/ready` route that pings the DB. The skill does **not** generate that by default — `/health` should never depend on external infrastructure (Kubernetes pattern).
