# docker-recipes

Every `Dockerfile` and `docker-compose.yml` the skill writes. Database service blocks live in [database-recipes.md](database-recipes.md); they slot into the compose files marked `{{ db-service }}`.

---

## Yarn 4 in containers — the install pattern

Every Dockerfile follows this order:

1. `FROM node:20-alpine`
2. `RUN corepack enable && corepack prepare yarn@4.5.0 --activate`
3. `WORKDIR /app`
4. `COPY package.json .yarnrc.yml ./`
5. `COPY .yarn/releases ./.yarn/releases`
6. (Optional, if `yarn.lock` exists) `COPY yarn.lock ./`
7. `RUN yarn install` (no `--immutable` on first scaffold; CI uses `--immutable`)
8. `COPY . .`

Step 5 is the crucial one — without `.yarn/releases/yarn-4.5.0.cjs` in the image, `corepack` would have to fetch Yarn over the network. We commit the binary so builds are reproducible offline.

For first-time scaffolds we drop `--immutable` because `yarn.lock` doesn't exist yet. The Dockerfile uses plain `yarn install`; CI (which runs against a checked-in lockfile) uses `yarn install --immutable --immutable-cache`. The template handles both: `--immutable` is only present in `.github/workflows/ci.yml`, not in the Dockerfile.

---

## Backend API · `Dockerfile`

```dockerfile
FROM node:20-alpine
RUN apk add --no-cache tini && corepack enable && corepack prepare yarn@4.5.0 --activate
WORKDIR /app

# Copy Yarn 4 binary + manifest first so the install layer caches well
COPY package.json .yarnrc.yml ./
COPY .yarn/releases ./.yarn/releases
# yarn.lock is optional on first scaffold; copy if present
COPY yarn.lock* ./
RUN yarn install

COPY . .

ENV NODE_ENV=development
EXPOSE 3000
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["yarn", "dev"]
```

`tini` is added so `Ctrl-C` propagates properly to the Node process during `docker compose up`.

## Backend API · `docker-compose.yml`

```yaml
services:
  app:
    build: .
    user: "${UID:-1000}:${GID:-1000}"
    ports:
      - "${PORT:-3000}:3000"
    env_file: .env
    environment:
      - NODE_ENV=development
    volumes:
      - .:/app
      - /app/node_modules
      - /app/.yarn/cache
    {{ db-service-depends }}
  {{ db-service }}
{{ db-volumes }}
```

- `user:` block handles edge case **E21** (root-owned files on the host). `UID`/`GID` fall back to 1000 if unset, matching the default `node` user in the Alpine image.
- The anonymous `/app/node_modules` volume handles edge case **E22**: the host's empty `node_modules` directory won't shadow the container's installed deps.
- `/app/.yarn/cache` is also anonymous so the Yarn 4 cache survives container restarts without polluting the host.
- `{{ db-service-depends }}` becomes `depends_on: [db]` if a DB was chosen, otherwise empty.
- `{{ db-service }}` and `{{ db-volumes }}` are replaced from [database-recipes.md](database-recipes.md).

---

## CLI · `Dockerfile`

Same as backend, minus `EXPOSE`. `CMD` becomes:

```dockerfile
CMD ["yarn", "dev", "--", "hello", "world"]
```

(So `docker compose up` runs `bin/cli.ts hello world` by default. Users override with `docker compose run --rm app yarn dev <command> <args>`.)

## CLI · `docker-compose.yml`

```yaml
services:
  app:
    build: .
    user: "${UID:-1000}:${GID:-1000}"
    env_file: .env
    volumes:
      - .:/app
      - /app/node_modules
      - /app/.yarn/cache
    # For cron/worker variants, replace `command:` with the appropriate command
    # and uncomment `restart: unless-stopped`:
    # restart: unless-stopped
    {{ db-service-depends }}
  {{ db-service }}
{{ db-volumes }}
```

---

## Frontend React · `Dockerfile` (multi-stage)

```dockerfile
# --- dev stage (used by docker compose up) ---
FROM node:20-alpine AS dev
RUN corepack enable && corepack prepare yarn@4.5.0 --activate
WORKDIR /app

COPY package.json .yarnrc.yml ./
COPY .yarn/releases ./.yarn/releases
COPY yarn.lock* ./
RUN yarn install

COPY . .
EXPOSE 5173
CMD ["yarn", "dev", "--host"]

# --- build stage ---
FROM dev AS build
RUN yarn build

# --- prod stage (nginx) ---
FROM nginx:alpine AS prod
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
```

## Frontend React · `docker-compose.yml`

```yaml
services:
  app:
    build:
      context: .
      target: dev          # docker compose up uses the dev stage
    user: "${UID:-1000}:${GID:-1000}"
    ports:
      - "5173:5173"
    env_file: .env
    volumes:
      - .:/app
      - /app/node_modules
      - /app/.yarn/cache
```

`docker compose up` boots the Vite dev server. For a production-style local check, run `docker build --target prod -t {{name}}:prod . && docker run --rm -p 8080:80 {{name}}:prod`.

## Frontend React · `nginx.conf`

```nginx
server {
  listen 80;
  server_name _;

  root /usr/share/nginx/html;
  index index.html;

  # SPA fallback — every non-asset path falls through to index.html
  location / {
    try_files $uri $uri/ /index.html;
  }

  # Long-cache hashed assets
  location /assets/ {
    expires 1y;
    add_header Cache-Control "public, immutable";
  }
}
```

---

## Fullstack · root `docker-compose.yml`

```yaml
services:
  api:
    build:
      context: ./apps/api
    user: "${UID:-1000}:${GID:-1000}"
    ports:
      - "3000:3000"
    env_file: .env
    environment:
      - NODE_ENV=development
    volumes:
      - ./apps/api:/app
      - /app/node_modules
      - /app/.yarn/cache
      - ./packages/shared:/packages/shared:ro
    {{ db-service-depends-on-api }}

  web:
    build:
      context: ./apps/web
      target: dev
    user: "${UID:-1000}:${GID:-1000}"
    ports:
      - "5173:5173"
    env_file: .env
    volumes:
      - ./apps/web:/app
      - /app/node_modules
      - /app/.yarn/cache
      - ./packages/shared:/packages/shared:ro
    depends_on: [api]

  {{ db-service }}
{{ db-volumes }}
```

The `packages/shared` bind mount is read-only so neither app accidentally writes into the shared package at runtime.

## Fullstack · `Dockerfile.tools`

```dockerfile
# Used for repo-wide commands: `docker compose -f docker-compose.tools.yml run --rm tools yarn workspaces foreach -A run lint`
FROM node:20-alpine
RUN corepack enable && corepack prepare yarn@4.5.0 --activate
WORKDIR /repo
CMD ["yarn", "--version"]
```

For workspace-wide commands, users either run `yarn workspaces foreach -A run <cmd>` inside any one of the existing services (workspaces are visible from any of them since they all bind the repo root) or build a separate `tools` compose file:

```yaml
# docker-compose.tools.yml
services:
  tools:
    build:
      context: .
      dockerfile: Dockerfile.tools
    user: "${UID:-1000}:${GID:-1000}"
    volumes:
      - .:/repo
      - /repo/node_modules
      - /repo/.yarn/cache
    working_dir: /repo
```

Use: `docker compose -f docker-compose.tools.yml run --rm tools yarn workspaces foreach -A run lint`.

---

## Monorepo · `docker-compose.yml`

```yaml
services:
  tools:
    build:
      context: .
      dockerfile: Dockerfile.tools
    user: "${UID:-1000}:${GID:-1000}"
    volumes:
      - .:/repo
      - /repo/node_modules
      - /repo/.yarn/cache
    working_dir: /repo
    # No `command` — invoke with `docker compose run --rm tools <cmd>`.
```

## Monorepo · `Dockerfile.tools`

Same as fullstack's.

---

## Library · `Dockerfile`

```dockerfile
FROM node:20-alpine
RUN corepack enable && corepack prepare yarn@4.5.0 --activate
WORKDIR /app

COPY package.json .yarnrc.yml ./
COPY .yarn/releases ./.yarn/releases
COPY yarn.lock* ./
RUN yarn install

COPY . .

# No EXPOSE, no CMD — invoke with `docker compose run --rm app <yarn-script>`.
CMD ["yarn", "test"]
```

## Library · `docker-compose.yml`

```yaml
services:
  app:
    build: .
    user: "${UID:-1000}:${GID:-1000}"
    volumes:
      - .:/app
      - /app/node_modules
      - /app/.yarn/cache
```

No ports. No DB. Just enough to run `yarn test` and `yarn build`.

---

## Edge cases the recipes guard against

| # | Symptom | Where this file handles it |
| --- | --- | --- |
| **E21** | Files created by the container are owned by `root` on the host. | Every service has `user: "${UID:-1000}:${GID:-1000}"`. |
| **E22** | The host's empty `node_modules/` directory shadows the container's install. | Anonymous `/app/node_modules` volume on every service. |
| Yarn cache invalidation between runs | The `.yarn/cache` directory churns and slows installs. | Anonymous `/app/.yarn/cache` volume. |
| Slow rebuilds when only source changed | Yarn install layer would re-run if `COPY . .` came before the install. | We `COPY package.json` + `yarn.lock` first, then install, then `COPY . .`. |
| Yarn not in the image | Corepack would have to fetch it. | We `COPY .yarn/releases` before install so corepack uses the local binary. |
| `Ctrl-C` doesn't stop the dev server | Node doesn't receive SIGINT cleanly. | Backend Dockerfile uses `tini` as PID 1. |
