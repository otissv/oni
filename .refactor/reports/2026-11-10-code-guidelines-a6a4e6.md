# Refactor report — 2026-11-10-code-guidelines-a6a4e6

- **Skill:** code-guidelines
- **Scope:** turn native file dialogs
- **Started:** 2026-11-10T14:24:06.679Z on `main` at `b7126cee98f5`
- **Outcomes:** kept 0, reverted 0, rejected 0, skipped 1, suggested 0, not-applied 0

## Decisions

| Id | Candidate / guideline | Outcome | Gate / reason | Why | Alternatives | Details |
|---|---|---|---|---|---|---|
| 1 | needless-wrapper | skipped |  | The private adapter bridges the Odin backend procedure type used by deterministic tests to the native C calling convention; direct aliasing changes its type. |  |  |
