---
name: widget
description: >-
  Author Oni widgets in widgets/ following the controlled, props-declared,
  Layout/Draw two-pass pattern. Use when creating or editing widgets,
  components, *_Config/*_Props/*_State types, theme_base, compound Trigger/
  Content parts, or when the user mentions Button, Checkbox, Popover, or
  WIDGETS.md.
---

# Oni widget authoring

## Before writing code

1. Read [docs/WIDGETS.md](../../../docs/WIDGETS.md) for the full checklist and skeleton.
2. Open the matching example below and mirror its structure — do not invent a parallel API.

## Example widgets (canonical)

| Pattern | File | Use when |
| ------- | ---- | -------- |
| Simple interactive / chrome | [widgets/button.odin](../../../widgets/button.odin) | Default template for almost every new widget |
| Controlled domain value | [widgets/checkbox.odin](../../../widgets/checkbox.odin) | App-owned value on `config` + `on_*_change` |
| Compound (root + parts + ctx) | [widgets/popover.odin](../../../widgets/popover.odin) | Shared open state; also read `popover_trigger.odin`, `popover_content.odin`, `popover_shared.odin` |
| Compound in-flow panel | [widgets/collapsible.odin](../../../widgets/collapsible.odin) | Expand/collapse in layout flow; also read `collapsible_trigger.odin`, `collapsible_content.odin`, `collapsible_shared.odin` |

## Production bar

Fully implement for production, without backwards compatibility, legacy or temporary code. Ensure defense-in-depth and all manual memory is cleaned up with appropriate allocators, including tests. Exit criteria is when you can clearly and confidently say there are no gaps in the implementation.

## Hard rules

- `*_Config` = data only (style + domain). Never `proc` fields.
- `*_Props` = `config` + procedures only (`child`, `on_*`, …). Non-procs belong on config.
- Disable via `config.disabled` / `set.Disabled`, not a props-level `disabled`.
- Branch on `o.ui_pass()`: Layout = lifecycle + children + return; Draw = interaction + paint + children + dispatch.
- Same tree both passes (ids, children order, conditionals).
- Controlled: domain on `config` every frame; report changes only through `on_*`.
- Style defaults in private `*_theme_base` via `set.*`; set `kind`.
- Prefer shared helpers (`widget_refresh_merged`, `widget_run_layout_lifecycle`, `widget_handle_interaction`, `widget_children`, `widget_dispatch_events`, …).
- Compound: private ctx in `*_shared.odin`, push/pop on root, clear in shutdown; register `*_shutdown` in `widgets/test_helpers.odin` `with_widget_env` (before `ui_init` and in defer).
- Do not edit `docs/*` or `.cursor/*`

## Workflow

1. Pick template: Button (default) → Checkbox (domain value) → Popover (compound).
2. Define `*_Config` / `*_State` / `*_Event` / `*_Props`.
3. Implement `*_theme_base` and the main proc mirroring the chosen example.
4. Compound: wire `*_shutdown` into `test_helpers.odin` `with_widget_env`.
5. Add `*_test.odin`; run `./oni/scripts/test_all.sh widgets`.

## Related

- Narrative model: [docs/ARCHITECTURE.md](../../../docs/ARCHITECTURE.md)
- Style fields: [docs/attributes.md](../../../docs/attributes.md)
- Contributor norms: [AGENTS.md](../../../AGENTS.md)
