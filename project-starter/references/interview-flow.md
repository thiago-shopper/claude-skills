# interview-flow

Exact `AskUserQuestion` payloads. Copy these verbatim — do not paraphrase the labels or descriptions.

---

## Round 1

Always asked. One call with all four questions.

```jsonc
{
  "questions": [
    {
      "question": "What kind of project are you starting?",
      "header": "Type",
      "multiSelect": false,
      "options": [
        { "label": "Backend API",        "description": "Express + TypeScript + Yarn 4. HTTP service with a /health endpoint and room for more routes." },
        { "label": "CLI / script / job", "description": "Node binary or long-running job. Includes a bin/cli.ts entrypoint and a commands/ folder." },
        { "label": "Frontend React app", "description": "Vite + React + TypeScript. Module-per-page, lazy-loaded, two main layouts and a shared/ folder." },
        { "label": "Fullstack app",      "description": "Backend API + Frontend React in one repo via Yarn 4 workspaces, plus a packages/shared/ for cross-stack types." },
        { "label": "Monorepo",           "description": "Yarn 4 workspaces with apps/ + packages/ + tools/. One starter package included; you add the rest." },
        { "label": "Library / package",  "description": "Publishable TS library. Generates declaration files, exports map, and publishConfig." }
      ]
    },
    {
      "question": "What's the project name? (kebab-case recommended — type in 'Other')",
      "header": "Name",
      "multiSelect": false,
      "options": [
        { "label": "my-project",   "description": "Generic placeholder — use 'Other' to enter the real name." },
        { "label": "scaffold-test","description": "Use this if you're just exercising the skill and will throw it away." }
      ]
    },
    {
      "question": "Include a working hello-world implementation?",
      "header": "Hello world",
      "multiSelect": false,
      "options": [
        { "label": "Yes (Recommended)", "description": "Backend: /health route returning {status:'ok'}. Frontend: a home module that renders the project name. CLI: a `hello` command. Library: an exported `hello()` function. Everything passes its first test on scaffold." },
        { "label": "No (skeleton only)","description": "Only the folder structure, configs, and Dockerfile. You write the first code." }
      ]
    },
    {
      "question": "Wire this project up for Claude Code?",
      "header": "Claude wire",
      "multiSelect": false,
      "options": [
        { "label": "Yes (Recommended)", "description": "Generates CLAUDE.md (50–70 lines: stack, conventions, commands, where new modules go) and .claude/settings.json (allowlists docker/git/yarn commands for fewer permission prompts)." },
        { "label": "No",                "description": "Skip both files. You can run /init later to bootstrap CLAUDE.md from the scaffolded state." }
      ]
    }
  ]
}
```

**Post-Round-1 validation:**
- If `Name` came back as one of the placeholder labels, prompt the user to override via "Other" and retry.
- Sanitize: lowercase, replace whitespace/underscores with `-`, drop anything that isn't `[a-z0-9-]`. Show before/after if it changed; ask the user to confirm. Edge case **E2**.
- Reject if the sanitized name is empty or starts/ends with `-`.

---

## Round 2 — Backend API / Fullstack / Monorepo

Splits into 2a and 2b because the question set is too large for one call.

### Round 2a

```jsonc
{
  "questions": [
    {
      "question": "Backend architecture style?",
      "header": "Architecture",
      "multiSelect": false,
      "options": [
        { "label": "Modular monolith (Recommended)", "description": "Feature-per-module under src/modules/<name>/. Each module owns its routes/controller/service/schema. Shared infra in src/shared/. Clear boundaries, easy to extract a module into its own service later." },
        { "label": "Layered",                        "description": "Flat src/{routes,services,repositories}/ split. Simpler for small projects, but couples features to layer files as the project grows." },
        { "label": "Clean Architecture",             "description": "Per-module entities/ usecases/ interfaces/ infra/. Strict dependency rule (inward only). Heavier ceremony — pick if your team already practices it." },
        { "label": "Hexagonal (Ports & Adapters)",   "description": "Per-module domain/ ports/ adapters/. Ports define interfaces, adapters implement them. Great for swapping infrastructure (DB, queue, HTTP) without touching domain." }
      ]
    },
    {
      "question": "CI provider?",
      "header": "CI/CD",
      "multiSelect": false,
      "options": [
        { "label": "GitHub Actions (Recommended)", "description": ".github/workflows/ci.yml — runs yarn install --immutable, lint, test, build on push and PR." },
        { "label": "GitLab CI",                    "description": ".gitlab-ci.yml with the same jobs." },
        { "label": "None",                         "description": "No CI workflow generated. You can add one later." }
      ]
    },
    {
      "question": "Database?",
      "header": "Database",
      "multiSelect": false,
      "options": [
        { "label": "MySQL 8 (Recommended)", "description": "mysql:8 service in docker-compose.yml, mysql2 driver in package.json, src/shared/db/client.ts with a connection pool." },
        { "label": "PostgreSQL 16",         "description": "postgres:16 service, pg driver, equivalent client wrapper." },
        { "label": "SQLite",                "description": "better-sqlite3 driver, file-backed in ./data/db.sqlite, no separate compose service." },
        { "label": "None",                  "description": "No DB wiring. src/shared/db/ is not generated." }
      ]
    },
    {
      "question": "Auth scaffold?",
      "header": "Auth",
      "multiSelect": false,
      "options": [
        { "label": "None (Recommended)",            "description": "No auth files generated. Keeps the scaffold lean. You can run the skill again with auth=yes to add it later (manually overlay the auth files)." },
        { "label": "JWT (jsonwebtoken)",            "description": "Stateless tokens, signed with HS256. AuthAdapter implemented via jsonwebtoken sign/verify. Refresh token + /auth/refresh route generated." },
        { "label": "Session (express-session)",     "description": "Cookie-based sessions. Adapter wraps express-session. /auth/me hydrates the user from the cookie." },
        { "label": "OAuth stub",                    "description": "Redirect-based OAuth flow. Adapter is a stub — you'll plug in a provider (Auth0, Keycloak, custom)." }
      ]
    }
  ]
}
```

### Round 2b

```jsonc
{
  "questions": [
    {
      "question": "API documentation?",
      "header": "API docs",
      "multiSelect": false,
      "options": [
        { "label": "OpenAPI/Swagger (Recommended)", "description": "Generates openapi.yaml at the repo root (documenting /health and the response envelope) and mounts /docs via swagger-ui-express." },
        { "label": "None",                          "description": "No openapi.yaml, no /docs route, no swagger dependency." }
      ]
    },
    {
      "question": "Proceed with this plan?",
      "header": "Confirm",
      "multiSelect": false,
      "options": [
        { "label": "Proceed (Recommended)", "description": "Create the files and run the Docker build + verify." },
        { "label": "Edit choices",          "description": "Go back to Round 2a and re-pick." },
        { "label": "Cancel",                "description": "Abort the skill. Nothing is written." }
      ]
    }
  ]
}
```

---

## Round 2 — Frontend React

Single round, three questions.

```jsonc
{
  "questions": [
    {
      "question": "CI provider?",
      "header": "CI/CD",
      "multiSelect": false,
      "options": [
        { "label": "GitHub Actions (Recommended)", "description": ".github/workflows/ci.yml — install, lint, test, build." },
        { "label": "GitLab CI",                    "description": ".gitlab-ci.yml with the same jobs." },
        { "label": "None",                         "description": "No CI workflow generated." }
      ]
    },
    {
      "question": "Auth scaffold?",
      "header": "Auth",
      "multiSelect": false,
      "options": [
        { "label": "None (Recommended)",            "description": "No auth files. Skip the auth module and shared/auth/." },
        { "label": "JWT (token in memory)",         "description": "AuthAdapter stores the access token in memory + refresh via /auth/refresh. LoginPage, RegisterPage, ForgotPasswordPage generated under modules/auth/." },
        { "label": "Session (cookie-based)",        "description": "Adapter calls /auth/me on mount to hydrate user from the session cookie." },
        { "label": "OAuth stub",                    "description": "Redirect-based flow. Adapter is a stub — you'll plug in a provider." }
      ]
    },
    {
      "question": "Proceed with this plan?",
      "header": "Confirm",
      "multiSelect": false,
      "options": [
        { "label": "Proceed (Recommended)", "description": "Create the files and run the Docker build + verify." },
        { "label": "Edit choices",          "description": "Re-pick CI / Auth." },
        { "label": "Cancel",                "description": "Abort. Nothing is written." }
      ]
    }
  ]
}
```

---

## Round 2 — CLI / script / job

Single round, three questions.

```jsonc
{
  "questions": [
    {
      "question": "CI provider?",
      "header": "CI/CD",
      "multiSelect": false,
      "options": [
        { "label": "GitHub Actions (Recommended)", "description": ".github/workflows/ci.yml — lint + test." },
        { "label": "GitLab CI",                    "description": ".gitlab-ci.yml with the same jobs." },
        { "label": "None",                         "description": "No CI workflow generated." }
      ]
    },
    {
      "question": "Does this CLI / job need a database?",
      "header": "Database",
      "multiSelect": false,
      "options": [
        { "label": "No (Recommended)", "description": "Most CLIs and jobs don't need a DB. Skip the compose db service and the client wrapper." },
        { "label": "MySQL",            "description": "mysql:8 in compose, mysql2 driver, src/shared/db/client.ts." },
        { "label": "PostgreSQL",       "description": "postgres:16 in compose, pg driver." },
        { "label": "SQLite",           "description": "better-sqlite3, file-backed at ./data/db.sqlite." }
      ]
    },
    {
      "question": "Proceed with this plan?",
      "header": "Confirm",
      "multiSelect": false,
      "options": [
        { "label": "Proceed (Recommended)", "description": "Create the files and run the Docker build + verify." },
        { "label": "Edit choices",          "description": "Re-pick CI / Database." },
        { "label": "Cancel",                "description": "Abort. Nothing is written." }
      ]
    }
  ]
}
```

---

## Round 2 — Library / package

Single round, three questions.

```jsonc
{
  "questions": [
    {
      "question": "CI provider?",
      "header": "CI/CD",
      "multiSelect": false,
      "options": [
        { "label": "GitHub Actions (Recommended)", "description": "ci.yml runs lint + test; release.yml publishes on tag." },
        { "label": "None",                         "description": "No CI workflow generated." }
      ]
    },
    {
      "question": "Publish target?",
      "header": "Target",
      "multiSelect": false,
      "options": [
        { "label": "Public npm (Recommended)", "description": "publishConfig.access = 'public'. Sets up release.yml to publish on tag." },
        { "label": "Private registry",         "description": "publishConfig.registry placeholder — you fill in the URL." },
        { "label": "Local only",               "description": "private:true. No publish wiring." }
      ]
    },
    {
      "question": "Proceed with this plan?",
      "header": "Confirm",
      "multiSelect": false,
      "options": [
        { "label": "Proceed (Recommended)", "description": "Create the files and run the Docker build + verify." },
        { "label": "Edit choices",          "description": "Re-pick CI / Target." },
        { "label": "Cancel",                "description": "Abort. Nothing is written." }
      ]
    }
  ]
}
```

---

## How to handle "Other" answers

`AskUserQuestion` always surfaces an "Other" option. Per-question handling:

| Question      | "Other" handling                                                                                              |
| ------------- | ------------------------------------------------------------------------------------------------------------- |
| Type          | Politely decline. List the six supported types. Edge case **E12**.                                            |
| Name          | Treat as the literal project name. Sanitize per the rules above.                                              |
| Hello world   | Treat as "No". Confirm with the user before scaffolding.                                                      |
| Claude wire   | Treat as "No". Confirm with the user before scaffolding.                                                      |
| Architecture  | Decline. Pick from the four listed.                                                                            |
| CI/CD         | Decline. Pick from the listed providers; ask the user to pick "None" if their tool isn't listed.              |
| Database      | Decline. Pick from the listed engines.                                                                         |
| Auth          | Decline. Pick from None / JWT / Session / OAuth stub.                                                          |
| API docs      | Decline. Pick OpenAPI or None.                                                                                 |
| Confirm       | Treat as Cancel. Do not proceed.                                                                               |
