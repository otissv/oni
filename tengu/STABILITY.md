# Tengu API Stability

Tengu is a standalone animation package. It does not depend on `oni` or any other project code.

## Current Release

- Version: `1.0.0`
- Stability: **stable**

## Semantic Versioning

Tengu follows [Semantic Versioning 2.0.0](https://semver.org/):

- **MAJOR** — breaking public API or documented behavior changes
- **MINOR** — backward-compatible feature additions
- **PATCH** — backward-compatible bug fixes and hardening

Version constants live in `version.odin`:

- `VERSION_MAJOR`, `VERSION_MINOR`, `VERSION_PATCH`
- `VERSION_STRING`
- `version_at_least(major, minor, patch)`

## Stable Public Surface

The following are committed for `1.x`:

### Contracts

- `Animatable(T)`, `Step_Result(T)`, `Completion_Policy`, `Time_Policy`
- `plan_substeps`, `is_done`, `snap_if_done`
- Built-in value types: `Vec2`, `Vec3`, `Vec4`, `RGBA`, `Rect`

### Compound values

- `Compound_Field_Entry`, `compound_entry_*`, `compound_zero`, `compound_add`, `compound_bind`
- `Panel_Style`, `Panel_Style_Animatable` (reference compound adapter)

### Primitives

- `Tween_Config`, `Tween_State`, `tween_init`, `tween_step`, `tween_seek`, `tween_sample_at`
- `Spring_Config`, `Spring_State`, `spring_init`, `spring_step`, `spring_set_target`
- `Keyframes_Spec`, `Keyframes_Config`, `Keyframes_State`, `keyframes_compile`, `keyframes_step`
- `Decay_Config`, `Decay_State`, `decay_init`, `decay_step`, `decay_set_velocity`

### Immediate-mode slots

- `Slot(T)`, `Start_Policy`, `transition_to`, `spring_to`, `tween_to`

### Composition

- `Stepper(T)`, `stepper_step`, `delay`, `sequence`, `parallel`, `repeat`, `stagger`

### Timeline

- `Timeline_Spec`, `Timeline_Config`, `Timeline_State`, `timeline_compile`, `timeline_step`, `timeline_seek`

### Diagnostics

- Progress, elapsed, target, and status queries on animators and steppers
- `validate_*_config` procs and `Config_Validity`
- Debug trace hooks (`set_animation_trace_hook`) in debug builds

### Hardening

- `sanitize_dt`, `is_finite`, `step_value_is_finite`

## Non-Guaranteed Surface

These may change in minor releases without a major bump:

- `@(private)` symbols
- Debug-only trace hooks and assertions
- Benchmark harness under `bench/`
- Internal compile error enums beyond their public meaning

## Behavior Guarantees

1. Callers own all animation state; the package keeps no hidden scheduler.
2. `dt` is always provided by the caller in seconds.
3. Negative or NaN `dt` never advances state.
4. Large `dt` for motion primitives is substepped deterministically via `Time_Policy`.
5. Target changes on springs and slots continue from the current displayed value unless `Start_Policy.FROM_START` is set.
6. Completion snaps to target when `Completion_Policy.snap_to_target` is true.

## Compatibility Policy

- Patch releases fix bugs without changing intended behavior covered by tests.
- Minor releases add types, procs, or enum variants without removing or renaming existing public symbols.
- Major releases may change contracts, completion semantics, or remove deprecated APIs.
