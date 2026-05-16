# Voice rules

The output should read like one engineer telling another what they need to know to be productive in 10 minutes. Short, direct, factual. Never marketing.

---

## Do

- **Write short sentences.** Subject — verb — object. Cut anything that doesn't carry information.
- **Use prose for descriptive sections.** What it is, why it exists, architecture overview. Sentences, not bullets.
- **Use bullets for genuine lists.** Commands, env vars, integrations, related projects. If a "list" would be one item, write it as a sentence instead.
- **Quote real commands in backticks.** Exactly as they appear in `scripts` / `Makefile` / the project's actual usage.
- **Use the project's own terminology.** Pull verbatim from manifests, code, existing docs. If the codebase calls something a "fulfillment center", don't rename it to "warehouse" in the README.
- **Mark inferences explicitly.** When you have to infer from indirect evidence, tag the sentence: `(inferred from Dockerfile — verify)`. Never silently guess.
- **Link to other docs when they exist.** "See [ARCHITECTURE.md](./ARCHITECTURE.md)" — don't duplicate content across files.

## Don't

- **No marketing words.** See `banned-words.md`. *Seamless, robust, powerful, enterprise-grade, blazing-fast, simply, easily, intuitive, comprehensive, leverage, unlock, empower, streamline.* Every one of these adds zero information.
- **No hedge words.** *Aims to, designed to, intended to, helps to, allows you to.* If the project does it, say it does it.
- **No filler openings.** *This project is a…* / *Welcome to…* / *In this repository you'll find…* / *This README will guide you through…*
- **No boilerplate Prerequisites section.** "Node.js, npm, git, a code editor" — if the Node version matters, put `node >= 20` as one line under Tech stack and move on.
- **No invented commands.** If no test script exists, don't write `npm test`. If no deploy mechanism exists, don't write `npm run deploy`.
- **No invented URLs, ports, package names, env var names, paths.** Everything traces back to a file you read.
- **No emoji in headings.** Unless the file being refreshed already uses them, in which case match the existing style.
- **No badges.** Unless the file being refreshed already has them.
- **No "Made with love" / "Built with ❤️" footers.** Unless already present in a refreshed file.
- **No bullet padding.** Stacks of single-word bullets ("Fast", "Easy", "Secure") are not information.

---

## Worked examples

### Tagline

> **Bad:** "A seamless, powerful, enterprise-grade order processing solution."
> **Good:** "Receives orders from the storefront, validates inventory, and writes them to Postgres."

### What it is

> **Bad:** "This robust project aims to provide a comprehensive solution for processing invoices, designed to empower teams to streamline their workflow."
> **Good:** "Indexes invoices from the FTP drop, normalizes the fields the finance team cares about, and exports a daily CSV to S3."

### Testing

> **Bad:**
> ```
> ## Testing
>
> This project has tests. Run them to make sure things work.
> ```
> **Good:**
> ```
> ## How to test
>
> `npm run test` runs Vitest against `src/`. `npm run test:e2e` spins up the docker-compose stack and runs Playwright.
> ```

### Prerequisites (omit it)

> **Bad:**
> ```
> ## Prerequisites
>
> - Node.js
> - npm
> - A terminal
> ```
> **Good:** omit the section. If Node version matters, put `node >= 20` as one line under Tech stack.

### Deploy

> **Bad:** "Deployment is handled through our CI/CD pipeline which seamlessly orchestrates the deployment process."
> **Good:** "Pushes to `main` trigger `.github/workflows/deploy.yml`, which builds the image and pushes to ECR; the service runs on Fargate per `infra/main.tf`."

### Permissions table

> **Bad** (half-empty table):
>
> | Claim | Purpose | Required for | Notes |
> |---|---|---|---|
> | admin | TBD | TBD | TBD |
> | user | TBD | TBD | TBD |
>
> **Good** (the data you actually have):
>
> | Claim | Purpose | Required for |
> |---|---|---|
> | `orders:read` | Read order history | GET `/orders/*` |
> | `orders:write` | Create or update orders | POST/PUT `/orders/*` |

---

## When to prefer prose vs bullets

| Section | Form |
|---|---|
| Title + tagline | Prose |
| What it is | Prose |
| Why it exists | Prose |
| Tech stack | Bullets |
| Setup | Numbered list |
| Env vars | Table or bullets |
| How to run | Mixed — prose for the explanation, code block for the command |
| How to test | Same as How to run |
| How to deploy | Prose |
| Architecture overview | Prose |
| Permissions | Table (or bullets if data is sparse) |
| Integrations | Bullets |
| Related projects | Bullets |
| Contributing | Prose |
| License | One line |

If you ever find yourself bulleting a single sentence, write it as a sentence instead.
