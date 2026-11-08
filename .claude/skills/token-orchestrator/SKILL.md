---
name: token-orchestrator
description: Use for coding, debugging, repo exploration, UI changes and testing when token efficiency matters. Selectively delegate isolated tasks to low-cost Claude Code subagents, minimize context and verification, and preserve work safely.
---

# Token Orchestrator

## Objective
Minimize total session token consumption and time while preserving correctness. Subagents are not automatically cheaper: use them only when isolation or parallelism outweigh their startup and context cost.

## Before work
1. Inspect `git status --short`, current branch, and relevant project instructions. Never assume another agent's changes are committed.
2. Identify exact deliverable, affected files, risks and minimum verification.
3. Search filenames/symbols first (`rg --files`, `rg -n`); read only relevant sections. Do not repeatedly dump entire files, logs or diffs.
4. Make a short internal plan; do not produce lengthy planning prose for small changes.

## Delegation decision
- **Direct in main agent:** one-file edits, obvious fixes, short searches, small UI tweaks. Avoid subagent overhead.
- **Haiku / low effort scout:** broad independent file discovery, locating symbols, summarizing noisy logs. Read-only. Return <= 250 words with paths and line references.
- **Sonnet / medium effort implementer:** bounded implementation with clear acceptance criteria and independent file ownership.
- **Opus / high effort specialist:** only when architectural decisions, cross-system concurrency, or stubborn failures justify it. Do not use Opus for routine searches or tests.
- Spawn at most 2 subagents concurrently by default. Never split work across agents editing the same files. Do not create subagents recursively unless clearly necessary.
- If available model names differ, select the lowest capable supported model. Effort levels are guidance, not a guarantee of tool support.

## Agent task contract
Each delegated task must specify:
- Goal and acceptance criteria
- Exact file paths / search scope
- Read-only or writable permission and exclusive file ownership
- Relevant constraints (engine, platform, user decisions)
- Minimum necessary tests
- Return format: `Findings | Files changed | Tests and results | Risks/blockers` (<= 250 words)
Do not paste whole repo context into agents. Never delegate a task solely to save main-agent reasoning if its own context cost is higher.

## Implementation
- Prefer minimal targeted diffs and existing conventions.
- Batch related edits. Avoid gratuitous refactors, formatting churn, dependency installation or broad asset regeneration.
- Do not revisit settled design decisions without a concrete conflict.
- Keep outputs short; cite paths rather than pasting large file contents.

## Testing budget
- Run only the smallest relevant syntax/import/targeted test or engine validation for modified behavior.
- For cosmetic changes, skip broad test suites; run a lightweight parse/build check only if required to catch a likely failure.
- Do not repeat passing tests without subsequent relevant changes.
- Escalate to broader testing only when targeted checks expose cross-cutting risk.
- Capture verbose output to files; return only errors and concise summaries.

## Git and release safety
- Preserve unrelated uncommitted work. Inspect before editing; never overwrite another agent's changes.
- Before committing, review only changed files and verify staged scope.
- Do not push, release, deploy or build/distribute an APK unless explicitly authorized.
- Record worktree/branch, modified files, tests, and uncommitted work in handover notes when stopping.

## Context and handover
- Keep durable notes in a short `WORK_STATUS.md` only for multi-session tasks, updating rather than duplicating history.
- Record decisions, files changed, remaining tasks, known failures, and git status.
- Use context compaction at natural milestones; do not repeatedly re-read the same background documents.

## Final response
Report only: completed work, verification, remaining blockers, and commit/push/release status. No lengthy narration, repeated prompts, or speculative follow-up work.
