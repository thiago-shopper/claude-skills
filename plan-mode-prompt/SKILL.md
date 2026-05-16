---
name: plan-mode-prompt
description: |
  Use this skill when the user wants to turn a rough draft, vague idea, or
  one-liner into a focused Plan-Mode-ready Claude prompt. Trigger phrases:
  "plan mode prompt", "build a plan prompt", "help me write a planning
  prompt", "I want to plan X" (when X is vague), "/plan-mode-prompt".

  Behavior:
  - If the draft is short or missing core info, the skill asks 2–4
    clarifying questions via AskUserQuestion (one round, clickable
    options), then emits the brief.
  - If the draft is already detailed (multi-paragraph, with goal + at
    least two of: audience, constraints, timeline, success metric), the
    skill skips questions and emits directly.
  - Output is a tight, topical, bullet-driven brief whose sections match
    the request (no fixed 14-section template, no template padding).

  After emitting, if Plan Mode is already active in this session OR the
  user signals agreement, you (Claude) MUST adopt the emitted prompt as
  the binding input brief for the planning that follows.
version: 2.0.0
allowed-tools: [Read, AskUserQuestion]
argument-hint: <rough draft of what you want to plan>
---

# plan-mode-prompt

Turn a rough draft into a focused prompt for Claude Plan Mode. This skill speaks **to you, Claude**: follow the workflow below to emit a single fenced markdown block.

The skill asks the user 2–4 targeted clarifying questions (via `AskUserQuestion`) **only when the draft doesn't carry enough signal**. When the draft is already detailed — multi-paragraph, with a clear goal plus at least two of: audience, constraints, timeline, success metric — the skill skips the question step and goes straight to emitting.

The emitted brief is **topical, bullet-driven, and adapted to the request**. Sections that aren't relevant to the topic are omitted entirely — no padding with template defaults, no "TBD".

The emitted brief is more than an artifact for copy-paste. **If Plan Mode is already active in this session, or the user signals agreement** ("I agree", "looks good", "go ahead", "proceed"), **you (Claude) MUST then treat the brief as the binding input brief** for the planning that follows. Its sections constrain the resulting plan, and the final plan file must address each one. Do not drift to a different structure.

---

## When to use

Invoke this skill when:

- The user runs `/plan-mode-prompt <draft>`.
- The user says "help me build a Plan Mode prompt", "turn this into a planning prompt", or pastes a rough idea and asks for a structured brief.
- The user types a vague planning intent like "I want to launch X", "help me plan Y", "I want to learn Z".

Do **not** invoke this skill when:

- The request is to *execute* something, even if framed as planning.
- The user has already supplied a complete, well-structured brief (Guardrail-style preamble + clearly-headed sections) — in that case, plan directly; don't re-wrap their brief.

Note: it's fine to invoke this skill while Plan Mode is already active — the emitted brief then serves as the input brief for the current planning turn (see Step 10).

---

## Workflow

1. **Capture the draft.** Take the argument to `/plan-mode-prompt`. If empty, use the user's most recent message. Don't ask "what would you like to plan?" — work with whatever you have.

2. **Detect the plan type** (advisory). Lowercase the draft and check keywords in this priority order, stopping at the first hit:

   | Keywords (any match) | Plan type |
   |---|---|
   | `launch`, `gtm`, `release`, `product launch`, `go-to-market` | `launch` |
   | `newsletter`, `podcast`, `book`, `blog`, `youtube`, `content series`, `substack` | `content` |
   | `learn`, `study`, `course`, `bootcamp`, `roadmap` (skill-focused), `master`, `pick up` | `learning` |
   | `event`, `conference`, `meetup`, `workshop`, `hackathon`, `unconference` | `event` |
   | `app`, `service`, `feature`, `migration`, `refactor`, `infra`, `api`, `library`, `saas`, `mvp` (with engineering verbs like *build*, *ship*, *deploy*, *architect*) | `software` |
   | (no match) | `generic` |

3. **Read the matching `references/<type>.md`** — use it as **advisory context** (likely-relevant topics, common risks, conventional horizons). Do not let it dictate which sections appear.

4. **Assess draft sufficiency.** A draft is **sufficient** when it:
   - clearly states a goal, **AND**
   - covers at least two of: audience, constraints, timeline horizon, success metric, hard requirements.

   Otherwise insufficient. Word count is a tiebreaker only — a 500-word draft missing the goal is still insufficient; a one-sentence draft with all the basics is rare but possible.

5. **If insufficient, ask 2–4 clarifying questions via `AskUserQuestion`.** Rules:
   - **One round only.** Do not chain rounds.
   - Each question must target a **load-bearing decision** the brief can't be written without: audience, timeline horizon, success threshold, scope boundary, output artifact.
   - 2–4 mutually exclusive options per question. Include a "Recommended" option first when one clearly dominates.
   - **Never re-ask** anything the draft already states.
   - If the user picks "Other" with vague text, or skips, treat that as a labeled assumption in the emitted brief — don't ask again.

   If sufficient, skip this step.

6. **Pick the topical sections that fit this request.** Use the three-tier rule under "Output sections — adaptive" below. **Omit any section that would be empty or padded.**

7. **Generate the brief as topical bullets.** Body style:
   - 1–3 bullets per section unless the user explicitly provided more detail.
   - Tight sentences. No filler. No marketing language.
   - Pull from the user's own framing where possible; quote verbatim phrases when they're load-bearing.
   - **Never invent** proper nouns, numerical thresholds, dates, or rationale that the draft or answers didn't provide.

8. **Run the quality checklist** (below) silently. Fix anything that fails before emitting.

9. **Emit the brief** as a single fenced markdown code block, preceded by exactly one short sentence — pick the variant matching the context:

   - **Plan Mode is NOT active** (skill is producing a prompt for the user to paste elsewhere):
     > Here is your Plan Mode prompt — review the assumptions, then paste it into a new Plan Mode session.
   - **Plan Mode IS active** in this session:
     > Here is the brief I'll use to drive the planning — confirm or correct the assumptions before I continue.

   Nothing else after the block.

10. **Adopt the brief as the binding input brief** — but only if **Plan Mode is active in this session** OR **the user has signaled agreement**. From this point on:

    - The emitted brief is the authoritative input for the planning work that follows.
    - **Preferred output format** is the contract for the final plan artifact — produce exactly what it asks for, in that structure. Do NOT drift to a different layout.
    - Every **Assumption (consolidated)** line is a constraint to honor (or explicitly override and call out in the plan).
    - Every **Risk** must be addressed in the plan with its stated mitigation woven in.
    - Every **Success criterion** must appear as a verification step in the plan.
    - **Constraints / Resources / Timeline** define the scope boundaries — the plan stays within them.
    - If the user pushes back on an assumption after emit, update that section in-place (or note the override in the final plan) and continue — don't restart.

    If neither condition is met, **stop after Step 9**. The user is taking the brief to a new session.

---

## Output sections — adaptive

Three tiers. The brief includes sections from tiers 1 and 2 always (when there's content for them) and tier 3 only when the topic warrants. **Omit anything that would be empty or padded.**

### Tier 1 — Always emit (Plan-Mode-interop scaffolding)

- **Guardrail** — first line, verbatim:
  > Do not execute, implement, create files, run tools, or take action yet. First, only analyze the request and produce a plan. Wait for my explicit approval before executing anything.
- **Goal** (`## Goal`) — 1 sentence.
- **Approval required** (`## Approval required`) — closing line, restating the guardrail in one sentence.

### Tier 2 — Emit when derivable from the draft or the user's answers

- **Context** (`## Context`) — 1–3 bullets paraphrasing the user's framing.
- **Constraints** (`## Constraints`) — only what the user stated or what answers surfaced.
- **Success criteria** (`## Success criteria`) — only if a measurable can be stated honestly (do **not** invent thresholds).
- **Preferred output format** (`## Preferred output format`) — the artifact Plan Mode should produce.

### Tier 3 — Emit only when topically relevant

- **Audience** — when the plan's output is consumed by someone other than the user.
- **Timeline** / **Milestones** — when the plan is time-bound or has sequenced checkpoints.
- **Resources** — when what's already on hand materially shapes the plan.
- **Dependencies** — when external blockers exist.
- **Risks** — when failure modes are non-trivial; each item has a `→ mitigation:` field.
- **Assumptions (consolidated)** — only if there are assumptions worth surfacing (typically: user picked "Other" with vague text in Step 5, or a load-bearing detail was inferred from context).

---

## Gap-filling rules

- **Critical gaps** (goal, output format) → ask via `AskUserQuestion` at Step 5.
- **Non-critical gaps** in optional sections → **omit** the section entirely. Don't pad with template defaults.
- **Critical gaps that survive the question round** (user picked "Other" with vague text, or skipped) → label as `**Assumption (please correct if wrong):**` inline in the relevant section.

Never write `TBD`. Never invent thresholds, dates, proper nouns, or rationale.

---

## Quality checklist (run silently before emitting)

1. Guardrail is the first line, verbatim.
2. Final line is the Approval-required restatement.
3. Goal section is 1 sentence.
4. Every emitted section pulls from the draft or the user's answers — no template padding.
5. No section has more than 3–4 bullets unless the user explicitly provided that much detail.
6. No invented proper nouns.
7. No invented numerical thresholds, dates, or names.
8. Body (after Goal, before Approval line) ≤ 250 words for typical drafts; hard cap 400.
9. Output is a single fenced markdown code block with a one-line preface.
10. If the draft was sufficient (Step 4), no questions were asked.
11. If questions were asked, none repeated information the draft already stated.

If any check fails, fix it and re-check.

---

## Example A — short/vague draft (insufficient → questions → focused brief)

### Draft

```
/plan-mode-prompt I want to plan a podcast
```

### Step 5: questions asked

Three questions via `AskUserQuestion`:

1. **Audience & topic** — "Tech founders / Indie developers / General curious learners / Other".
2. **Format & cadence** — "Weekly 30-min solo / Biweekly 45-min interview / Monthly 60-min mixed / Other".
3. **First success target** — "100 listeners/episode by ep 10 / 1,000 by ep 20 / Top-10 in category by ep 30 / Other".

Suppose the user picks: *Indie developers* / *Biweekly 45-min interview* / *1,000 by ep 20*.

### Emitted (after Step 9)

> Here is your Plan Mode prompt — review the assumptions, then paste it into a new Plan Mode session.

````markdown
Do not execute, implement, create files, run tools, or take action yet. First, only analyze the request and produce a plan. Wait for my explicit approval before executing anything.

## Goal
Launch a biweekly 45-minute interview podcast for indie developers.

## Context
- Solo operator starting from scratch.
- Format and audience locked: biweekly 45-min interviews aimed at indie devs.

## Constraints
- Cadence: biweekly.
- Episode length: ~45 minutes, interview format.

## Success criteria
- 1,000 listeners per episode by episode 20.

## Preferred output format
A 20-episode release plan covering guest pipeline, recording/edit cadence, and a distribution checklist. Surface anything I didn't specify (hosting, equipment, intro music, etc.).

## Approval required
Wait for my explicit approval before executing anything.
````

~115 words. No Audience section (already in Goal), no Timeline/Milestones, Risks, Resources, Dependencies, or Assumptions — those weren't load-bearing for this request.

---

## Example B — long/detailed draft (sufficient → no questions → focused brief)

### Draft

```
/plan-mode-prompt I want to make another change on that skill. I think the
final prompt is coming too long, I want the user input to be more
structured, more detailed, clearly, but it doesn't have to be long, maybe
the skill should focus more on the original idea and let Claude make the
questions. Actually, it should have instruction to make a few questions by
default. It also has to consider that the user may writes a long and
detailed prompt. This prompt itself is a good example of something that
the skill will have to deal with.
```

### Step 4 assessment

Sufficient: goal stated ("make another change on that skill"); covers constraints (shorter output, focused on original idea), behavior requirements (ask a few questions by default, handle long input), and gives an in-context example (this very draft). Skip Step 5.

### Emitted (after Step 9)

> Here is your Plan Mode prompt — review the assumptions, then paste it into a new Plan Mode session.

````markdown
Do not execute, implement, create files, run tools, or take action yet. First, only analyze the request and produce a plan. Wait for my explicit approval before executing anything.

## Goal
Modify the plan-mode-prompt skill so its emitted brief is shorter, more focused on the user's original idea, and so Claude asks a few clarifying questions by default.

## Context
- The current emitted brief is too long.
- The user wants the brief to be more structured, detailed, and clear — but not lengthy.
- The skill should let Claude pose a few clarifying questions to the user instead of always filling gaps with assumptions.

## Constraints
- Ask a few clarifying questions by default.
- Handle both short/vague drafts and long/detailed drafts (this very draft is an example of the long case).
- Output should focus on the original idea — not pad with template defaults.

## Preferred output format
A revised SKILL.md plus a description of what changes in workflow, output-section rules, and gap-handling rules. Surface trade-offs in how to detect "already-detailed" drafts versus short ones.

## Approval required
Wait for my explicit approval before executing anything.
````

~165 words. Mirrors the user's own framing; no Audience, Timeline, Risks, Resources, Dependencies, or invented success thresholds.

---

## Limits

- Heuristic plan-type detection. For genuinely cross-domain drafts (e.g. "build and launch an AI newsletter SaaS"), pick the highest-priority template and surface alternates as a labeled assumption.
- **At most one round of clarifying questions**, 2–4 questions in that round. The skill never chains rounds — if the answers leave gaps, those become labeled assumptions in the emitted brief.
- The skill never starts a Plan Mode session on its own. When Plan Mode is **not** active and the user hasn't agreed, the skill emits and stops — the user pastes the brief into a new session.
- When adopting the brief as the input brief (Step 10), the **Preferred output format** section is non-negotiable structure — match it exactly. A prior session saw Claude emit the brief and then drift into a different plan structure; Step 10 exists to prevent that.
