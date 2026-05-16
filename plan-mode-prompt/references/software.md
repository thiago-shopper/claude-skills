# software template

## When to use
Engineering work: building an app/service/feature, refactoring, infra change, migration, API or library design, MVP scope-out.

## Default audience
Internal engineering team (the user + colleagues). Possibly downstream users of the system if it's user-facing. No external customers by default unless the draft says so.

## Default timeline + milestones
- Horizon: **6 weeks**, in three 2-week sprints.
- Milestones:
  1. Sprint 1 end — design doc accepted; thinnest end-to-end slice running locally.
  2. Sprint 2 end — happy path working in staging; tests cover golden + first edge case.
  3. Sprint 3 end — production-ready; observability + rollback path documented; rollout plan signed off.

## Default resources
- One engineer (the user) for the build.
- Existing CI/CD, code review, monitoring stack.
- Standard cloud / Docker / language toolchain already in place.
- No new vendor / paid service unless the draft mentions one.

## Likely risks (template-derived)
- Hidden coupling with an existing system surfacing in Sprint 2 → mitigation: list every touched module on Day 1; require a brief sign-off from each module's primary owner.
- Migration / rollout step under-planned → mitigation: write the rollback procedure before writing migration code.
- Test coverage thinned to hit the deadline → mitigation: gate sprint review on test-pass + minimum coverage delta, not on demo-quality.
- Stale dependencies / version pinning issues during deploy → mitigation: lock versions in Sprint 1; do a dry-run deploy in Sprint 2.
- Scope creep ("while we're in here…") → mitigation: collect adjacent-improvement ideas in a parking lot doc; review at the next planning cycle, not this one.

## Default success criteria
- Leading metric: design doc reviewed and accepted by end of Sprint 1 (yes/no).
- Lagging metric: feature in production with zero rollback-triggering incidents in the first 14 days post-launch.

## Preferred output-format default
A sprint-by-sprint plan (3 sprints × 2 weeks), a list of files / modules to touch (with risk-of-coupling notes), a rollout + rollback plan, and a risk register. Call out any assumptions about the existing system that I should verify before approving.