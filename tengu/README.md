# Tengu

Tengu is a standalone Odin animation package. It does not depend on `oni` or any other project code.

Given previous animation state and a frame delta `dt`, Tengu produces the next value and a `done` flag. You own all state; Tengu keeps no hidden scheduler.

- Version: `1.0.0` (see [STABILITY.md](STABILITY.md) for API guarantees)
- Time units: **seconds**
- Negative or NaN `dt` never advances state
- **190** unit tests; every public procedure is covered

## Quick start

Import the package and step animations each frame with your frame delta:

```odin
import tengu "../tengu" // adjust path to your project layout

opacity_slot: tengu.Slot(f32)
dt := f32(frame_time_seconds)

tengu.slot_init(&opacity_slot, 0, .SPRING)

options := tengu.spring_slot_options(f32(0))
result := tengu.spring_to(&opacity_slot, 1, dt, options, tengu.F32_Animatable())

draw(opacity = result.value)
```

`result.done` is `true` when the animation has settled. `result.value` is the value to display this frame.

## Core model

Every animator follows the same pattern:

1. **You allocate and own state** (`Slot`, `Tween_State`, `Spring_State`, etc.).
2. **You pass `dt` every frame** in seconds.
3. **You pass an `Animatable(T)` adapter** so Tengu can mix, add, and measure distance for type `T`.
4. **You read `Step_Result(T)`** — `value`, optional `velocity`, and `done`.

```odin
result: tengu.Step_Result(f32)
// result.value        — display this frame
// result.velocity     — meaningful for springs and decay when result.has_velocity
// result.done         — animation finished (snapped to target when configured)
```

### Built-in value types

Tengu ships adapters for:

| Type | Adapter |
|------|---------|
| `f32` | `F32_Animatable()` or `animatable_of(my_f32)` |
| `Vec2` | `Vec2_Animatable()` |
| `Vec3` | `Vec3_Animatable()` |
| `Vec4` | `Vec4_Animatable()` |
| `RGBA` | `RGBA_Animatable()` (premultiplied-alpha interpolation) |
| `Rect` | `Rect_Animatable()` |

All built-in types work with every primitive (tween, spring, keyframes, decay, slots, composition, and timelines).

```odin
pos := tengu.Vec2{x = 10, y = 20}
anim := tengu.Vec2_Animatable()
// or: anim := tengu.animatable_of(pos)
```

### Compound structs

Animate several fields together by composing per-field adapters with `compound_entry_*` and `compound_bind`. Each field is mixed independently; compound distance is the Euclidean norm of per-field distances.

Odin procedure values cannot close over local state, so each compound type declares a field-entry table and six thin top-level procedures (see `Panel_Style` in `compound.odin` for the reference pattern):

```odin
Widget_Style :: struct {
    opacity: f32,
    offset:  Vec2,
}

widget_style_entries :: proc() -> [2]tengu.Compound_Field_Entry {
    return {
        tengu.compound_entry_f32(offset_of(Widget_Style, opacity)),
        tengu.compound_entry_vec2(offset_of(Widget_Style, offset)),
    }
}

widget_style_zero :: proc() -> Widget_Style {
    entries := widget_style_entries()
    return tengu.compound_zero(Widget_Style, entries[:])
}

// widget_style_add, sub, scale, mix, distance — same pattern, calling
// compound_add/sub/scale/mix/distance with entries[:]

Widget_Style_Animatable :: proc() -> tengu.Animatable(Widget_Style) {
    entries := widget_style_entries()
    return tengu.compound_bind(
        widget_style_zero,
        widget_style_add,
        widget_style_sub,
        widget_style_scale,
        widget_style_mix,
        widget_style_distance,
        tengu.compound_entries_have_velocity(entries[:]) ? .VALUE_TYPE : .NONE,
    )
}
```

Entry builders are available for `f32`, `Vec2`, `Vec3`, `Vec4`, `RGBA`, and `Rect`. Tengu also ships `Panel_Style` and `Panel_Style_Animatable` as a complete reference implementation.

## Immediate-mode slots (recommended for UI)

Slots are the ergonomic API for UI work. Each frame, declare the value you want and Tengu returns the animated value. Target changes continue from the **current displayed value** by default.

### Spring

```odin
slot: tengu.Slot(f32)
tengu.slot_init(&slot, 0, .SPRING)

options := tengu.spring_slot_options(f32(0)) // start used only with FROM_START
// or frequency-based tuning:
// options := tengu.spring_slot_options_from_frequency(f32(0), frequency = 2, damping_ratio = 0.8)

result := tengu.spring_to(&slot, target, dt, options, tengu.F32_Animatable())
```

### Tween

```odin
slot: tengu.Slot(f32)
tengu.slot_init(&slot, 0, .TWEEN)

options := tengu.tween_slot_options(
    f32(0),                    // start (used only with FROM_START)
    tengu.Seconds(0.3),        // duration
    delay = 0,
    easing = tengu.Ease.OUT_CUBIC,
)

result := tengu.tween_to(&slot, target, dt, options, tengu.F32_Animatable())
```

### Generic transition

If the slot already stores tween or spring options, use `transition_to`:

```odin
slot.spring_opts = tengu.spring_slot_options(f32(0))
result := tengu.transition_to(&slot, target, dt, tengu.F32_Animatable())
```

### Start policy

By default, changing the target mid-animation continues from where the value is now. To restart from an explicit start value instead:

```odin
tengu.slot_init(&slot, 0, .SPRING, .FROM_START)
options := tengu.spring_slot_options(f32(25)) // explicit start
_ = tengu.spring_to(&slot, 75, dt, options, tengu.F32_Animatable())
// next target change restarts from options.start
```

### Slot helpers

| Procedure | Purpose |
|-----------|---------|
| `slot_value` | Current displayed value |
| `slot_target` | Current target |
| `slot_is_done` / `slot_is_active` | Status queries |
| `slot_reset` | Jump to a value and stop animating |
| `slot_restart` | Replay the active transition |
| `slot_set_start_policy` | Change `FROM_CURRENT` / `FROM_START` |

## Low-level primitives

Use primitives directly when you want full control over init, seek, and reconfiguration.

### Tween

Duration-driven interpolation with easing, delay, and repeat.

```odin
state: tengu.Tween_State(f32)

tengu.tween_init(&state, tengu.Tween_Config(f32) {
    start    = 0,
    target   = 100,
    duration = tengu.Seconds(0.5),
    easing   = tengu.Ease.OUT_CUBIC,
    repeat_count = 1, // 0 = loop forever
})

result := tengu.tween_step(&state, dt, tengu.F32_Animatable())
tengu.tween_seek(&state, 0.25)           // jump to elapsed time
sample := tengu.tween_sample_at(state, 0.25, tengu.F32_Animatable()) // read without stepping
```

Easing can be a named `Ease` value or a cubic `Bezier{x1, y1, x2, y2}`. CSS presets are available: `Ease.CSS_EASE`, `CSS_EASE_IN`, etc.

### Spring

Physics-based motion with stiffness, damping, and mass.

```odin
state: tengu.Spring_State(f32)

tengu.spring_init(
    &state,
    tengu.spring_config(target = 100), // or spring_config_from_frequency
    start_value = 0,
)

result := tengu.spring_step(&state, dt, tengu.F32_Animatable())

// Mid-flight target change — position and velocity continue unchanged:
tengu.spring_set_target(&state, 50)
```

`spring_reconfigure` updates stiffness/damping/mass without resetting motion. `spring_restart` reapplies `initial_velocity` from a chosen value.

### Keyframes

Segmented duration-based animation. Compile once, then step.

```odin
stops := []tengu.Keyframe_Stop(f32) {
    tengu.keyframes_stop_duration(f32(10), tengu.Seconds(0.5), tengu.Ease.OUT_QUAD),
    tengu.keyframes_stop_duration(f32(20), tengu.Seconds(0.5)),
}
spec := tengu.keyframes_spec_duration(f32(0), stops)

config, err := tengu.keyframes_compile(spec)
defer tengu.keyframes_config_destroy(config)
if err != .NONE { /* handle compile error */ }

state: tengu.Keyframes_State(f32)
tengu.keyframes_init(&state, config)
result := tengu.keyframes_step(&state, dt, tengu.F32_Animatable())
```

Offset-based timing normalizes stops along a total duration:

```odin
stops := []tengu.Keyframe_Stop(f32) {
    tengu.keyframes_stop_offset(f32(10), 0.5),
    tengu.keyframes_stop_offset(f32(20), 1.0),
}
spec := tengu.keyframes_spec_offset(f32(0), stops, tengu.Seconds(2.0))
```

### Decay (inertia)

Velocity-driven motion with exponential friction. Useful for scroll fling and drag release.

```odin
state: tengu.Decay_State(f32)

tengu.decay_init(
    &state,
    tengu.decay_config(initial_velocity = 500), // pixels per second, for example
    start_value = scroll_offset,
)

result := tengu.decay_step(&state, dt, tengu.F32_Animatable())

// User grabs mid-fling:
tengu.decay_set_velocity(&state, new_velocity)
```

Bounded motion with clamp or bounce. Supported for `f32`, `Vec2`, `Vec3`, `Vec4`, and `Rect`:

```odin
config := tengu.decay_config_bounded(
    initial_velocity,
    bounds_min = 0,
    bounds_max = max_scroll,
    bounds_mode = .BOUNCE,
)

// Vec2 scroll fling with per-axis bounds:
config := tengu.decay_config_bounded(
    tengu.Vec2{120, -80},
    bounds_min = tengu.Vec2{0, 0},
    bounds_max = tengu.Vec2{max_x, max_y},
    time_constant = 0.35,
    bounds_mode = .CLAMP,
)
```

`decay_reconfigure` updates parameters while preserving the current motion. `decay_restart` reapplies `initial_velocity` from a chosen value.

## Composition

Primitives and combinators share a uniform `Stepper(T)` interface.

```odin
fast: tengu.Tween_State(f32)
slow: tengu.Tween_State(f32)
// ... tween_init both ...

steppers := [2]tengu.Stepper(f32) {
    tengu.tween_stepper(&fast),
    tengu.tween_stepper(&slow),
}

// Parallel — all children step each frame; primary_index selects the returned value
parallel: tengu.Parallel_State(f32)
tengu.parallel_init(&parallel, steppers[:], primary_index = 0)
result := tengu.parallel_step(&parallel, dt, tengu.F32_Animatable())

// Sequence — children run one after another
sequence: tengu.Sequence_State(f32)
tengu.sequence_init(&sequence, steppers[:])
result := tengu.sequence_step(&sequence, dt, tengu.F32_Animatable())

// Delay — hold a value, then run a child
delay: tengu.Delay_State(f32)
tengu.delay_init(&delay, tengu.tween_stepper(&fast), delay = 0.2, hold_value = 0)
result := tengu.delay_step(&delay, dt, tengu.F32_Animatable())

// Repeat — replay a child for N cycles (0 = infinite)
repeat: tengu.Repeat_State(f32)
tengu.repeat_init(&repeat, tengu.tween_stepper(&fast), repeat_count = 3, cycle_start = 0)

// Stagger — offset each child by interval * index
stagger: tengu.Stagger_State(f32)
holds := []f32{0, 0, 0}
err := tengu.stagger_init(&stagger, children[:], holds, interval = 0.1)
defer tengu.stagger_destroy(stagger)
```

Use `stepper_step`, `stepper_is_done`, and `stepper_restart` on any `Stepper(T)`.

## Timelines

Timelines orchestrate multiple tracks with offsets and named labels. Overlapping tracks run in parallel.

```odin
alpha: tengu.Tween_State(f32)
beta: tengu.Tween_State(f32)
// ... init tweens ...

tracks := []tengu.Timeline_Track_Spec(f32) {
    tengu.timeline_track_spec("fade", 0, tengu.tween_stepper(&alpha), hold_value = 0),
    tengu.timeline_track_spec("slide", tengu.Seconds(0.2), tengu.tween_stepper(&beta), hold_value = 0),
}
labels := []tengu.Timeline_Label {
    tengu.timeline_label("intro", 0),
}

spec := tengu.timeline_spec(tracks, labels, primary_index = 0)
config, err := tengu.timeline_compile(spec, tengu.F32_Animatable())
defer tengu.timeline_config_destroy(config)

timeline: tengu.Timeline_State(f32)
tengu.timeline_init(&timeline, spec, config)
defer tengu.timeline_destroy(timeline)

result := tengu.timeline_step(&timeline, dt, tengu.F32_Animatable())
tengu.timeline_seek(&timeline, tengu.Seconds(0.5))
```

Keep all referenced stepper state alive for the lifetime of the timeline.

## Policies

### Completion

```odin
policy := tengu.Completion_Policy {
    distance_epsilon     = 1e-4,  // how close counts as "at target"
    rest_speed_threshold = 1e-4,  // how slow counts as "at rest"
    snap_to_target       = true,  // snap to exact target when done
}
result := tengu.spring_step(&state, dt, anim, policy)
```

### Large frame times

Springs and decay substep large `dt` deterministically:

```odin
time := tengu.Time_Policy {
    max_dt       = 1.0 / 30.0,
    max_substeps = 8,
}
result := tengu.spring_step(&state, dt, anim, completion, time)
```

## Diagnostics

Query progress without changing stepping behavior:

```odin
tengu.tween_progress(state)
tengu.spring_displacement(state.value, state.config.target, anim)
tengu.slot_status(slot)
tengu.slot_is_idle(slot)
```

Validate configuration before init:

```odin
validity := tengu.validate_spring_config(config)
if validity != .VALID { /* handle */ }
```

In debug builds, register a trace hook to log steps:

```odin
when ODIN_DEBUG {
    tengu.set_animation_trace_hook(f32, proc(info: tengu.Trace_Info(f32), _: rawptr) {
        // inspect info.value, info.done, info.progress, etc.
    })
}
```

Traced slot variants (`spring_to_traced`, `tween_to_traced`, `transition_to_traced`) emit trace events automatically.

## Hardening

Numeric guards for production stepping:

```odin
safe_dt := tengu.sanitize_dt(raw_dt)          // non-positive and NaN dt → 0
tengu.is_finite(result.value)                 // per-type finite checks
tengu.step_value_is_finite(step_result)       // value and velocity when present
```

Fuzz and golden-frame tests in `tengu_test.odin` verify deterministic behavior under bad frame times and non-finite inputs.

## Typical UI patterns

### Animate a property toward a layout target each frame

```odin
@(private)
panel_x: tengu.Slot(f32)

@(private)
draw_panel :: proc(target_x: f32, dt: f32) {
    if !panel_initialized {
        tengu.slot_init(&panel_x, target_x, .SPRING)
        panel_initialized = true
    }

    opts := tengu.spring_slot_options_from_frequency(f32(0), 3, 0.85)
    result := tengu.spring_to(&panel_x, target_x, dt, opts, tengu.F32_Animatable())
    render_at(x = result.value)
}
```

### Mount / unmount lifecycle

See `app/app.odin` for a full example: spring in on mount, tween out on unmount, returning a done flag to the UI framework.

### Interruptible fling

```odin
on_drag_end :: proc(velocity: f32) {
    tengu.decay_set_velocity(&scroll_decay, velocity)
}
// each frame:
result := tengu.decay_step(&scroll_decay, dt, tengu.F32_Animatable())
scroll_offset = result.value
```

## Running tests and benchmarks

From the repository root (with `tengu/` as the package directory):

```bash
odin test tengu
```

Benchmark harness (separate `tengu_bench` package):

```bash
odin run tengu/bench -o:speed
```

## Further reading

- [STABILITY.md](STABILITY.md) — semver policy and stable public API
- [animation.md](animation.md) — internal implementation plan (not user documentation)
