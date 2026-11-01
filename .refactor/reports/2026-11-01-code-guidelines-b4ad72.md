# Refactor report — 2026-11-01-code-guidelines-b4ad72

- **Skill:** code-guidelines
- **Scope:** turn M7 widgets editing and Tengu
- **Started:** 2026-11-01T15:12:25.035Z on `main` at `965fc2aecea7`
- **Outcomes:** kept 1, reverted 0, rejected 0, skipped 0, suggested 0, not-applied 0

## Changes

| Id | Where | Guideline | Source | Before → after | Why | Origin | Outcome |
|---|---|---|---|---|---|---|---|
| 1 | templates/vector_gallery.odin:692 | dead-code | agent | `values[0].target = persistent.m7_body values[0].target = {}` → `values[0].target = {}` | The definition target is immediately cleared when selecting an occurrence; remove the overwritten assignment. | uncommitted (implementer) | kept |
