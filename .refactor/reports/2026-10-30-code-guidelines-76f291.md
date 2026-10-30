# Refactor report — 2026-10-30-code-guidelines-76f291

- **Skill:** code-guidelines
- **Scope:** turn: accordion widget and supporting types
- **Started:** 2026-10-30T18:59:53.065Z on `main` at `f8d0a5a2486c`
- **Outcomes:** kept 1, reverted 0, rejected 0, skipped 0, suggested 0, not-applied 0

## Changes

| Id | Where | Guideline | Source | Before → after | Why | Origin | Outcome |
|---|---|---|---|---|---|---|---|
| 1 | widgets/accordion_parts.odin:116 | nested-conditional | agent | `if drawing { for key in tab_order { if key == trigger.key { append(...) } } }` → `if drawing { for key in tab_order { if key != trigger.key { continue }; append(.` | Use an early continue to keep trigger registration out of a third nested branch. | uncommitted (implementer) | kept |
