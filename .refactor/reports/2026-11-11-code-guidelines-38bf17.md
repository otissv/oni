# Refactor report — 2026-11-11-code-guidelines-38bf17

- **Skill:** code-guidelines
- **Scope:** turn debug overlay, renderer counters and transient text shaping
- **Started:** 2026-11-11T19:40:52.936Z on `main` at `9060d2c7a860`
- **Outcomes:** kept 1, reverted 0, rejected 0, skipped 0, suggested 0, not-applied 0

## Changes

| Id | Where | Guideline | Source | Before → after | Why | Origin | Outcome |
|---|---|---|---|---|---|---|---|
| 1 | font_shaper.odin:1415 | nested-conditional | agent | `if cache { font_shape_cache_insert(...); if cached, ok := font_shape_cache_looku` → `Return frame-owned shapes early when cache is disabled; keep cache insertion and` | Keeps transient shaping explicit and avoids a third nested conditional without changing ownership or results. | uncommitted (implementer) | kept |
