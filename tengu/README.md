# Tengu

Tengu is a standalone Odin animation package. It does not depend on any other packages.

Given previous animation state and a frame delta `dt`, Tengu produces the next value and a `done` flag. You own all state; Tengu keeps no hidden scheduler.

- Version: `1.0.0` (see [STABILITY.md](STABILITY.md) for API guarantees)
- Time units: **seconds**
- Negative or non-number `dt` never advances state

## Quick start

Import the package and step animations each frame with your frame delta:

```odin
import tengu "../tengu" // adjust path to your project layout

opacity_slot: tengu.Slot(f32)
dt := f32(frame_time_seconds)

tengu.slot_init(tengu.Slot_Init_Params(f32){
    slot = &opacity_slot, 
    value = 0, 
    kind = .SPRING
})

options := tengu.Spring_Slot_Options(f32){ 
    start = f32(0), 
    stiffness = tengu.DEFAULT_SPRING_STIFFNESS, 
    damping = tengu.DEFAULT_SPRING_DAMPING, 
    mass = tengu.DEFAULT_SPRING_MASS
}

result := tengu.spring_to(tengu.Spring_To_Params(f32){
    slot = &opacity_slot,
    target = 1,
    dt = dt,
    options = options,
    anim = tengu.F32_Animatable(),
    completion = tengu.DEFAULT_COMPLETION_POLICY,
    time = tengu.DEFAULT_TIME_POLICY,
})

draw(opacity = result.value)
```

`result.done` is `true` when the animation has settled. `result.value` is the value to display this frame.

## Core model

Every animator follows the same pattern:

1. **You allocate and own state** (`Slot`, `Tween_State`, `Spring_State`, etc.).
2. **You pass `dt` every frame** in seconds.
3. **You pass an `Animatable(T)` adapter** so Tengu can mix, add, and measure distance for type `T`.
4. **You read `Step_Result(T)`** — `value`, optional `velocity`, and `done`.

Most stepping, slot, composition, and query procedures take a single `*_Params(T)` struct instead of positional arguments. Required policy fields have no defaults — pass `DEFAULT_COMPLETION_POLICY` and `DEFAULT_TIME_POLICY` where shown in the examples below.

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

widget_style_add :: proc(a, b: Widget_Style) -> Widget_Style {
    entries := widget_style_entries()
    return tengu.compound_add(tengu.Compound_Add_Params(Widget_Style){
        a = a, 
        b = b, 
        entries = entries[:]
    })
}

widget_style_mix :: proc(p: tengu.Mix_Params(Widget_Style)) -> Widget_Style {
    entries := widget_style_entries()
    return tengu.compound_mix(tengu.Compound_Mix_Ops_Params(Widget_Style){
        a = p.a, 
        b = p.b, 
        t = p.t, 
        entries = entries[:]})
}

// widget_style_sub, scale, distance — same pattern with Compound_Sub_Params,
// Compound_Scale_Params, and Compound_Distance_Params

Widget_Style_Animatable :: proc() -> tengu.Animatable(Widget_Style) {
    entries := widget_style_entries()
    return tengu.compound_bind(tengu.Compound_Bind_Params(Widget_Style){
        zero = widget_style_zero,
        add = widget_style_add,
        sub = widget_style_sub,
        scale = widget_style_scale,
        mix = widget_style_mix,
        distance = widget_style_distance,
        velocity_support = tengu.compound_entries_have_velocity(entries[:]) ? .VALUE_TYPE : .NONE,
    })
}
```

Entry builders are available for `f32`, `Vec2`, `Vec3`, `Vec4`, `RGBA`, and `Rect`. Tengu also ships `Panel_Style` and `Panel_Style_Animatable` as a complete reference implementation.

## Immediate-mode slots (recommended for UI)

Slots are the ergonomic API for UI work. Each frame, declare the value you want and Tengu returns the animated value. Target changes continue from the **current displayed value** by default.

### Spring

```odin
slot: tengu.Slot(f32)
tengu.slot_init(tengu.Slot_Init_Params(f32){
    slot = &slot, 
    value = 0, 
    kind = .SPRING
})

options := tengu.Spring_Slot_Options(f32){
    start = f32(0), // used only with FROM_START
    stiffness = tengu.DEFAULT_SPRING_STIFFNESS,
    damping = tengu.DEFAULT_SPRING_DAMPING,
    mass = tengu.DEFAULT_SPRING_MASS,
}
// frequency-based tuning example:
// options.stiffness = mass * (2πf)² ; options.damping = 2 * mass * ζ * (2πf)

result := tengu.spring_to(tengu.Spring_To_Params(f32){
    slot = &slot,
    target = target,
    dt = dt,
    options = options,
    anim = tengu.F32_Animatable(),
    completion = tengu.DEFAULT_COMPLETION_POLICY,
    time = tengu.DEFAULT_TIME_POLICY,
})
```

### Tween

```odin
slot: tengu.Slot(f32)
tengu.slot_init(tengu.Slot_Init_Params(f32){
    slot = &slot, 
    value = 0, 
    kind = .TWEEN
})

options := tengu.Tween_Slot_Options(f32){
    start = f32(0), // used only with FROM_START
    duration = tengu.Seconds(0.3),
    delay = 0,
    easing = tengu.Ease.OUT_CUBIC,
    repeat_count = 1,
    repeat_mode = .RESTART,
}

result := tengu.tween_to(tengu.Tween_To_Params(f32){
    slot = &slot,
    target = target,
    dt = dt,
    options = options,
    anim = tengu.F32_Animatable(),
    completion = tengu.DEFAULT_COMPLETION_POLICY,
})
```

### Generic transition

If the slot already stores tween or spring options, use `transition_to`:

```odin
slot.spring_opts = tengu.Spring_Slot_Options(f32){
    start = f32(0), 
    stiffness = tengu.DEFAULT_SPRING_STIFFNESS, 
    damping = tengu.DEFAULT_SPRING_DAMPING, 
    mass = tengu.DEFAULT_SPRING_MASS
}

result := tengu.transition_to(tengu.Transition_To_Params(f32){
    slot = &slot,
    target = target,
    dt = dt,
    anim = tengu.F32_Animatable(),
    completion = tengu.DEFAULT_COMPLETION_POLICY,
    time = tengu.DEFAULT_TIME_POLICY,
})
```

### Start policy

By default, changing the target mid-animation continues from where the value is now. To restart from an explicit start value instead:

```odin
tengu.slot_init(tengu.Slot_Init_Params(f32){
    slot = &slot, 
    value = 0, 
    kind = .SPRING, 
    start_policy = .FROM_START
})

options := tengu.Spring_Slot_Options(f32){
    start = f32(25), 
    stiffness = tengu.DEFAULT_SPRING_STIFFNESS, 
    damping = tengu.DEFAULT_SPRING_DAMPING, 
    mass = tengu.DEFAULT_SPRING_MASS
}

_ = tengu.spring_to(tengu.Spring_To_Params(f32){
    slot = &slot, target = 75,
    dt = dt, options = options, 
    anim = tengu.F32_Animatable(), 
    completion = tengu.DEFAULT_COMPLETION_POLICY, 
    time = tengu.DEFAULT_TIME_POLICY
})

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

result := tengu.tween_step(tengu.Step_Params(f32){
    state = &state, 
    dt = dt, 
    anim = tengu.F32_Animatable(), 
    completion = tengu.DEFAULT_COMPLETION_POLICY
})

tengu.tween_seek(&state, 0.25) // jump to elapsed time

// read without stepping
sample := tengu.tween_sample_at(state, tengu.Sample_At_Params(f32){
    elapsed = 0.25, 
    anim = tengu.F32_Animatable(), 
    completion = tengu.DEFAULT_COMPLETION_POLICY
}) 
```

Easing can be a named `Ease` value or a cubic `Bezier{x1, y1, x2, y2}`. CSS presets are available: `Ease.EASE`, `EASE_IN`, etc.

### Spring

Physics-based motion with stiffness, damping, and mass.

```odin
state: tengu.Spring_State(f32)

tengu.spring_init(tengu.Spring_Init_Params(f32){
    state = &state,
    config = tengu.Spring_Config(f32){
        target = 100, 
        stiffness = 200, 
        damping = 26, 
        mass = 1\
    },
    start_value = 0,
})

result := tengu.spring_step(tengu.Motion_Step_Params(f32){
    state = &state, 
    dt = dt, 
    anim = tengu.F32_Animatable(), 
    completion = tengu.DEFAULT_COMPLETION_POLICY, 
    time = tengu.DEFAULT_TIME_POLICY
})

// Mid-flight target change — position and velocity continue unchanged:
tengu.spring_set_target(&state, 50)
```

`spring_reconfigure` updates stiffness/damping/mass without resetting motion. `spring_restart` reapplies `initial_velocity` from a chosen value.

### Keyframes

Segmented duration-based animation. Compile once, then step.

```odin
stops := []tengu.Keyframe_Stop(f32) {
    {value = f32(10), duration = tengu.Seconds(0.5), easing = tengu.Ease.OUT_QUAD},
    {value = f32(20), duration = tengu.Seconds(0.5)},
}
spec := tengu.Keyframes_Spec(f32){
    start = f32(0), 
    stops = stops, 
    timing_mode = .DURATION,
    repeat_count = 1,
    repeat_mode = .RESTART
}

config, err := tengu.keyframes_compile(spec)
defer tengu.keyframes_config_destroy(config)
if err != .NONE { /* handle compile error */ }

state: tengu.Keyframes_State(f32)
tengu.keyframes_init(&state, config)
result := tengu.keyframes_step(tengu.Step_Params(f32){
    state = &state, 
    dt = dt, 
    anim = tengu.F32_Animatable(), 
    completion = tengu.DEFAULT_COMPLETION_POLICY
})
```

Offset-based timing normalizes stops along a total duration:

```odin
stops := []tengu.Keyframe_Stop(f32) {
    {value = f32(10), offset = 0.5},
    {value = f32(20), offset = 1.0},
}
spec := tengu.Keyframes_Spec(f32){
    start = f32(0), 
    stops = stops, 
    timing_mode = .OFFSET, 
    total_duration = tengu.Seconds(2.0), 
    repeat_count = 1, 
    repeat_mode = .RESTART
}
```

### Decay (inertia)

Velocity-driven motion with exponential friction. Useful for scroll fling and drag release.

```odin
state: tengu.Decay_State(f32)

tengu.decay_init(tengu.Decay_Init_Params(f32){
    state = &state,
    config = tengu.decay_config(initial_velocity = 500), // pixels per second, for example
    start_value = scroll_offset,
})

result := tengu.decay_step(tengu.Motion_Step_Params(f32){
    state = &state, 
    dt = dt, anim = tengu.F32_Animatable(), 
    completion = tengu.DEFAULT_COMPLETION_POLICY, 
    time = tengu.DEFAULT_TIME_POLICY
})

// User grabs mid-fling:
tengu.decay_set_velocity(&state, new_velocity)
```

Bounded motion with clamp or bounce. Supported for `f32`, `Vec2`, `Vec3`, `Vec4`, and `Rect`:

```odin
config := tengu.Decay_Config(f32){
    initial_velocity = initial_velocity,
    time_constant = tengu.DEFAULT_DECAY_TIME_CONSTANT,
    bounds_min = 0,
    bounds_max = max_scroll,
    bounds_mode = .BOUNCE,
    bounce = tengu.DEFAULT_DECAY_BOUNCE,
}

// Vec2 scroll fling with per-axis bounds:
config = tengu.Decay_Config(tengu.Vec2){
    initial_velocity = tengu.Vec2{120, -80},
    time_constant = 0.35,
    bounds_min = tengu.Vec2{0, 0},
    bounds_max = tengu.Vec2{max_x, max_y},
    bounds_mode = .CLAMP,
    bounce = tengu.DEFAULT_DECAY_BOUNCE,
}
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

tengu.parallel_init(tengu.Parallel_Init_Params(f32){
    state = &parallel, children = steppers[:], primary_index = 0})

result := tengu.parallel_step(tengu.Parallel_Step_Params(f32){
    state = &parallel, 
    dt = dt, 
    anim = tengu.F32_Animatable(), 
    completion = tengu.DEFAULT_COMPLETION_POLICY
})

// Sequence — children run one after another
sequence: tengu.Sequence_State(f32)

tengu.sequence_init(&sequence, steppers[:])

result := tengu.sequence_step(tengu.Sequence_Step_Params(f32){
    state = &sequence, 
    dt = dt, 
    anim = tengu.F32_Animatable(), 
    completion = tengu.DEFAULT_COMPLETION_POLICY
})

// Delay — hold a value, then run a child
delay: tengu.Delay_State(f32)

tengu.delay_init(tengu.Delay_Init_Params(f32){
    state = &delay, 
    child = tengu.tween_stepper(&fast),
    delay = 0.2, hold_value = 0
})

result := tengu.delay_step(tengu.Delay_Step_Params(f32){
    state = &delay, \
    dt = dt, 
    anim = tengu.F32_Animatable(), 
    \completion = tengu.DEFAULT_COMPLETION_POLICY
})

// Repeat — replay a child for N cycles (0 = infinite)
repeat: tengu.Repeat_State(f32)

tengu.repeat_init(tengu.Repeat_Init_Params(f32){
    state = &repeat, 
    child = tengu.tween_stepper(&fast), 
    repeat_count = 3, cycle_start = 0
})

result = tengu.repeat_step(tengu.Repeat_Step_Params(f32){
    state = &repeat, 
    dt = dt, 
    anim = tengu.F32_Animatable(), 
    completion = tengu.DEFAULT_COMPLETION_POLICY
})

// Stagger — offset each child by interval * index
stagger: tengu.Stagger_State(f32)
hold_values := []f32{0, 0, 0}
err := tengu.stagger_init(tengu.Stagger_Init_Params(f32){
    state = &stagger,
    children = children[:],
    hold_values = hold_values,
    interval = 0.1,
    primary_index = 0,
    allocator = context.allocator,
})
defer tengu.stagger_destroy(stagger)
```

Use `stepper_step`, `stepper_is_done`, and `stepper_restart` on any `Stepper(T)`:

```odin
stepper := tengu.tween_stepper(&fast)

result := tengu.stepper_step(tengu.Stepper_Step_Params(f32){
    stepper = stepper, 
    dt = dt, 
    anim = tengu.F32_Animatable(), 
    completion = tengu.DEFAULT_COMPLETION_POLICY
})

done := tengu.stepper_is_done(tengu.Stepper_Is_Done_Params(f32){
    stepper = stepper, 
    anim = tengu.F32_Animatable(), 
    completion = tengu.DEFAULT_COMPLETION_POLICY
})
```

## Timelines

Timelines orchestrate multiple tracks with offsets and named labels. Overlapping tracks run in parallel.

```odin
alpha: tengu.Tween_State(f32)
beta: tengu.Tween_State(f32)
// ... init tweens ...

tracks := []tengu.Timeline_Track_Spec(f32) {
    {name = "fade", offset = 0, stepper = tengu.tween_stepper(&alpha), hold_value = 0},
    {name = "slide", offset = tengu.Seconds(0.2), stepper = tengu.tween_stepper(&beta), hold_value = 0},
}
labels := []tengu.Timeline_Label {
    tengu.timeline_label("intro", 0),
}

spec := tengu.timeline_spec(tengu.Timeline_Spec_Params(f32){tracks = tracks, labels = labels, primary_index = 0})

config, err := tengu.timeline_compile(tengu.Timeline_Compile_Params(f32){
    spec = spec, 
    anim = tengu.F32_Animatable()
})
defer tengu.timeline_config_destroy(config)

timeline: tengu.Timeline_State(f32)
tengu.timeline_init(tengu.Timeline_Init_Params(f32){
    state = &timeline, 
    spec = spec, 
    config = config, 
    allocator = context.allocator
})
defer tengu.timeline_destroy(timeline)

result := tengu.timeline_step(tengu.Step_Params(f32){
    state = &timeline, 
    dt = dt, 
    anim = tengu.F32_Animatable(), 
    completion = tengu.DEFAULT_COMPLETION_POLICY
})

tengu.timeline_seek(tengu.Timeline_Seek_Params(f32){
    state = &timeline, elapsed = tengu.Seconds(0.5), 
    anim = tengu.F32_Animatable(), 
    completion = tengu.DEFAULT_COMPLETION_POLICY
})
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
result := tengu.spring_step(tengu.Motion_Step_Params(f32){
    state = &state, 
    dt = dt, anim = anim, 
    completion = policy, 
    time = tengu.DEFAULT_TIME_POLICY
})
```

### Large frame times

Springs and decay substep large `dt` deterministically:

```odin
time := tengu.Time_Policy {
    max_dt       = 1.0 / 30.0,
    max_substeps = 8,
}

result := tengu.spring_step(tengu.Motion_Step_Params(f32){
    state = &state, 
    dt = dt, 
    anim = anim, 
    completion = completion, 
    time = time
})
```

## Diagnostics

Query progress without changing stepping behavior:

```odin
tengu.tween_progress(state)
tengu.spring_displacement(tengu.Spring_Displacement_Params(f32){
    value = state.value, 
    target = state.config.target,
    anim = anim
})
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
    tengu.set_animation_trace_hook(f32, tengu.Set_Animation_Trace_Hook_Params(f32){
        callback = proc(info: tengu.Trace_Info(f32), _: rawptr) {
            // inspect info.value, info.done, info.progress, etc.
        },
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
        tengu.slot_init(tengu.Slot_Init_Params(f32){
            slot = &panel_x, 
            value = target_x, 
            kind = .SPRING
        })

        panel_initialized = true
    }

    // frequency ≈ 3 Hz, damping ratio ≈ 0.85 — tune stiffness/damping on Spring_Slot_Options
    opts := tengu.Spring_Slot_Options(f32){
        start = f32(0), 
        stiffness = 355, 
        damping = 32, 
        mass = 1
    }
    result := tengu.spring_to(tengu.Spring_To_Params(f32){
        slot = &panel_x, 
        target = target_x, 
        dt = dt, 
        options = opts, 
        anim = tengu.F32_Animatable(), 
        completion = tengu.DEFAULT_COMPLETION_POLICY, 
        time = tengu.DEFAULT_TIME_POLICY
    })

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
result := tengu.decay_step(tengu.Motion_Step_Params(f32){
    state = &scroll_decay,
    dt = dt, 
    anim = tengu.F32_Animatable(), 
    completion = tengu.DEFAULT_COMPLETION_POLICY, 
    time = tengu.DEFAULT_TIME_POLICY
})

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
