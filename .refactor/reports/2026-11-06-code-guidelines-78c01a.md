# Refactor report — 2026-11-06-code-guidelines-78c01a

- **Skill:** code-guidelines
- **Scope:** turn dialog focus trap
- **Started:** 2026-11-06T22:39:48.535Z on `main` at `b7126cee98f5`
- **Outcomes:** kept 1, reverted 0, rejected 0, skipped 0, suggested 0, not-applied 0

## Changes

| Id | Where | Guideline | Source | Before → after | Why | Origin | Outcome |
|---|---|---|---|---|---|---|---|
| 1 | types.odin:197 | dead-code | agent | `depth: int; scope.depth = scope.parent < 0 ? 0 : w_ctx.focus_scopes[scope.parent` → `Remove unused scope depth field and assignment` | Scope precedence follows layout declaration order; depth is never read. | uncommitted (implementer) | kept |
