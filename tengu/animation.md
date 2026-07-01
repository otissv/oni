# Animation Library Implementation Plan

This document defines the production-first implementation order for a standalone Odin animation package intended for immediate UI usage.

The package should be a pure animation engine:

- given previous animation state and `dt`, produce the next value
- return a `done` flag
- never own the UI tree
- never require fallback paths or legacy compatibility layers
- default to starting from the current displayed value when targets change
- only restart from an explicit start value when a dedicated flag or policy says to

The goal is that each implementation phase is complete on its own and does not require refactoring in later phases.

## Design Rule

Implement the package inside-out:

1. freeze contracts first
2. finalize core primitives second
3. build convenience APIs on top
4. build composition after primitives are stable
5. build timelines last as orchestration over existing stable parts

This prevents later layers from forcing rewrites in lower layers.

## Required Constraints

The package must follow these constraints from the beginning:

- caller owns all animation state
- the core owns no hidden global scheduler
- `dt` is always provided by the caller
- stepping is deterministic
- completion semantics are explicit and documented
- no API placeholders
- no "temporary" reduced versions to be rewritten later
- no fallback behavior branches
- no legacy compatibility surface

## Implementation Order

### 1. Freeze the core contracts

This phase must be completed before implementing any real animation type.

Define and finalize:

- animatable value requirements
  - `zero`
  - `add`
  - `sub`
  - `scale`
  - `mix`
  - `distance`
  - optional velocity support
- time semantics
  - `dt` units
  - max `dt` behavior
  - internal substepping rules
- completion semantics
  - what `done` means
  - when snapping occurs
  - epsilon and rest thresholds
- state ownership
  - caller-owned state only
- canonical step result
  - next value
  - next velocity if relevant
  - done flag

This phase is complete when:

- deterministic one-step tests can be written against the contract
- all future animation types can use the same state/result pattern
- no hidden retained-controller assumptions exist

If this phase is wrong, every later phase will require refactoring.

### 2. Build the math and interpolation kernel

Implement the full low-level utility layer next and treat it as stable infrastructure.

Include:

- `clamp`
- `wrap`
- `progress`
- `lerp`
- inverse lerp
- approximate equality
- angle mixing
- color interpolation policy
- easing functions
- cubic bezier solving
- value mixers for supported built-in types

This layer must:

- allocate nothing during stepping
- know nothing about UI
- know nothing about timelines or controllers

This phase is complete when:

- math behavior is fully tested
- easing outputs are reference-validated
- the mixing rules are documented and final

### 3. Implement `tween` as a complete production primitive

`Tween` is the first full runtime primitive because it establishes the final model for duration-driven animation.

Implement the final feature set immediately:

- duration
- easing
- delay
- repeat
- repeat modes if part of the final API
- elapsed time tracking
- seek
- exact completion snapping
- zero-duration behavior

Do not ship a reduced tween with the intention of redesigning it later.

This phase is complete when:

- `tween` is fully usable in production by itself
- the API is final
- tests cover completion, repeats, seeking, and edge conditions

### 4. Implement `spring` as a complete production primitive

This phase defines the package's most important transition behavior.

Choose one spring model and commit to it from the start:

- `stiffness` / `damping` / `mass`
- or `frequency` / `damping_ratio`

Then fully implement:

- initial velocity
- rest speed threshold
- rest displacement threshold
- internal handling for large `dt`
- exact snap-to-target completion
- deterministic interruption behavior
- mid-flight target change behavior that defaults to continuing from the current displayed value

This is the phase where the no-retarget-default design becomes final.

This phase is complete when:

- target changes do not require a special retarget API in the normal path
- spring behavior remains stable under poor frame pacing
- interruption semantics are clearly documented and tested

### 5. Implement the immediate-mode transition slot API

Only after `tween` and `spring` are final should the convenience API be added.

This layer should provide:

- persistent slot state per animated property
- default start-from-current behavior
- optional explicit start-from-start behavior
- target change detection
- config change detection
- reset and restart rules
- done queries

This layer must remain a thin wrapper over the already-final primitives.

Typical public surface:

- `transition_to`
- `spring_to`
- `tween_to`
- `Slot(T)`
- `Start_Policy`

This phase is complete when:

- immediate UI code can declare a desired value each frame and receive the current animated value back
- normal target changes do not require extra APIs
- widget-level code does not need to know about low-level stepping internals

### 6. Implement `keyframes`

After duration-based stepping is stable, add segmented animation.

Implement the final behavior up front:

- arbitrary value stops
- per-segment easing
- per-segment durations or normalized offsets
- delay
- repeat
- seek
- exact completion semantics matching `tween`

Do not treat this as a temporary chain of tweens with implementation leaks.

This phase is complete when:

- the keyframe data model is stable
- segment compilation is stable
- no redesign is needed to support later timeline work

### 7. Implement `decay` and `inertia`

This is the final major primitive and should be finalized before any high-level orchestration.

Implement:

- velocity-driven motion
- friction or time-constant behavior
- completion rules
- interruption rules
- bounds and bounce if they are part of the final API

Pick one clean physical model and commit to it. Do not ship overlapping variants.

This phase is complete when:

- decay or inertia can be used directly in production
- bounded and unbounded behavior is stable
- it composes cleanly with the other primitives

### 8. Implement composition primitives

Only once the primitive animators are stable should composition be added.

Implement in this order:

1. `delay`
2. `sequence`
3. `parallel`
4. `repeat`
5. `stagger`

All composition should operate on one stable animation protocol or equivalent stepper interface established earlier.

This phase is complete when:

- all combinators work uniformly with `tween`, `spring`, `keyframes`, and `decay`
- composition introduces no new state model
- no wrapper types will later need flattening or replacement

### 9. Implement `timeline`

Timeline should be built late, not early.

It should be a compiler and orchestration layer over already-stable primitives, not a separate execution engine.

Implement:

- timeline specification format
- immutable compiled timeline data
- tracks
- offsets
- labels
- overlaps
- seek
- progress inspection

This phase is complete when:

- timeline is built from existing primitives and composition operators
- it does not duplicate spring or tween logic
- timeline bugs do not require changes to low-level stepping internals

### 10. Expand supported value domains

Add more value types only after the core engine and orchestration layers are stable.

Add support in this order:

1. scalar
2. `Vec2`
3. `Vec3`
4. `Vec4`
5. color
6. rect or box-like types
7. compound structs

Each type must be added through stable adapters and mixers, not by changing core algorithms.

This phase is complete when:

- new value support is additive only
- the core runtime does not change for each new type
- compound animation does not introduce reflection-heavy hacks or special-case branches

### 11. Add observability and diagnostics

Production-ready libraries need introspection, but this must remain additive.

Add:

- progress queries
- elapsed time queries
- current target inspection
- active or idle state queries
- debug assertions
- optional trace hooks for debug builds

This phase is complete when:

- debugging and profiling support exist without changing core contracts
- observability does not force new ownership models

### 12. Harden, benchmark, and lock the package

This final phase turns the package from feature-complete into production-ready.

Complete:

- deterministic golden tests
- fuzz tests for invalid numeric behavior
- large-`dt` tests
- interruption tests
- seek and repeat edge-case tests
- timeline edge-case tests
- benchmarks
- API stability documentation
- semantic versioning policy

This phase is complete when:

- the public API can be committed to without planned redesign
- performance characteristics are measured
- the package is safe to release as a production dependency

## Dependency Order

The safe dependency chain is:

`contracts -> math -> tween/spring -> transition slots -> keyframes/decay -> composition -> timeline -> value expansion -> hardening`

Later phases should only depend on earlier phases. Earlier phases should never depend on convenience or orchestration layers.

## Minimal Release Milestones

### Milestone 1

- contracts
- math kernel
- `tween`
- `spring`
- scalar and vector support
- full tests for primitives

This is the first point where the package is meaningfully usable.

### Milestone 2

- transition slot API
- color and box-like value support
- finalized interruption semantics
- immediate UI documentation

This is the point where the package becomes ergonomic for immediate UI usage.

### Milestone 3

- `keyframes`
- `decay`
- `delay`
- `sequence`
- `parallel`
- `repeat`
- `stagger`

This is the point where the package becomes broadly feature-complete for most app and UI animation work.

### Milestone 4

- `timeline`
- compound value animation
- benchmarks
- API stability guarantees

This is the release point for a full `1.0`-quality package.

## Summary

The correct implementation order is:

1. freeze contracts
2. finalize math
3. finish `tween`
4. finish `spring`
5. add immediate-mode transition slots
6. finish `keyframes`
7. finish `decay` or `inertia`
8. add composition primitives
9. add timeline
10. expand value support
11. add diagnostics
12. harden and lock the release

This order ensures that every section is complete when introduced and that later sections are additive rather than forcing refactors of earlier work.
