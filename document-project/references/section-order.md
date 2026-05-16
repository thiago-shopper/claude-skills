# Section order

Canonical render order for any file the skill writes. Sections that don't fire are omitted entirely — the remaining sections keep this order.

## README.md

1. Title (H1) + one-line tagline
2. What it is
3. Why it exists
4. Tech stack at a glance
5. Setup
6. Environment variables
7. How to run
8. How to test
9. How to deploy *(or link to DEPLOYMENT.md)*
10. Architecture overview *(or link to ARCHITECTURE.md)*
11. Permissions / Claims
12. External setup / Integrations
13. Related projects
14. Contributing *(or link to CONTRIBUTING.md)*
15. License

## CONTRIBUTING.md

1. Title (H1) — "Contributing to <project>"
2. How to set up a dev environment *(references README's Setup; do not duplicate)*
3. How to run tests
4. Commit / PR conventions
5. Code review / CODEOWNERS *(if applicable)*
6. Code of conduct *(link, if file exists)*

## ARCHITECTURE.md

1. Title (H1) — "Architecture"
2. One-paragraph overview
3. Components / modules — one short paragraph per top-level module
4. Data flow / control flow
5. External dependencies (datastores, SaaS, queues)
6. ADRs / decisions *(link to `docs/adr*` if present)*

## DEPLOYMENT.md

1. Title (H1) — "Deployment"
2. Environments (dev / staging / prod, as evidence supports)
3. How a deploy happens (the actual mechanism — CI workflow, infra tool, etc.)
4. Required credentials / secrets — names only, never values
5. Rollback procedure *(only if evidence exists; do not invent)*
6. Monitoring / observability links *(only if evidence exists)*

## Cross-doc linking

When an extra file is generated, the README's corresponding section becomes a one-paragraph stub + link instead of duplicating content. Example:

```markdown
## Architecture

Three services share a Postgres database; see [ARCHITECTURE.md](./ARCHITECTURE.md) for the full breakdown.
```
