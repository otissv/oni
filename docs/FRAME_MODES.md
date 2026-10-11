# Frame modes

Oni supports different kinds of apps and games. Frame pacing is an **engine-wide**
policy: how the process idles and when it runs layout/draw/present. It is **not**
scoped per `Draw_Space` (screen / artboard / popover / overlay)—those are layers
inside a single frame.

Vendor libraries live in the **app layer**. Oni does not import or special-case
them. The app steps those libs and, when effective pacing is on-demand, calls
Oni’s generic wake API if another frame is needed.

## Modes

| Mode | Behavior | Typical use |
|------|----------|-------------|
| **Continuous** | Every host loop iteration runs tick → layout → draw → present (still paced by VSync when enabled), whether or not the window is focused. | Games and always-live viewports that must keep advancing in the background. |
| **On-demand** | The engine waits for input, a timeout, or an explicit wake. A full frame runs only when something needs one, focused or not. | Docs, settings UIs, editors at rest, reading-heavy tools. |
| **Focused** | **Focused:** same as continuous. **Unfocused:** same as on-demand (wait + dirty/wake; longer wait timeout is allowed to save CPU). Focus gain/loss wakes a frame so the transition is immediate. | Desktop apps and tools that should feel live while in use but idle when in the background. |

Effective pacing each loop iteration is whichever of the three modes is selected; there is no separate optional focus flag.

## How they work

### Continuous

1. Host calls `app_update` / `Run_Frame` every loop iteration.
2. Poll SDL events (non-blocking).
3. Always tick, layout, draw, and present when `can_render`.
4. VSync (swapchain) caps GPU rate; the CPU still does a full UI pass each frame.

### On-demand

1. When idle, wait on `SDL_WaitEventTimeout` (or equivalent)—not a busy spin.
2. Wake when:
   - an SDL event arrives (input, resize, focus, quit, …),
   - a **frame request** / wake deadline is pending,
   - the wait **timeout** fires (settings watch, hot-reload host, and similar engine housekeeping).
3. Run a normal frame: poll → tick → layout → draw → present.
4. Clear one-shot dirty flags after present; keep waking if a wake deadline is still active.
5. Optionally skip present when nothing is dirty (secondary optimization; wait is the main idle path).

Timeouts matter: on-demand must not block forever, or settings mtime checks and hot reload stall. They are **not** a substitute for app wake calls—ongoing app work must push wake explicitly.

### Focused

1. Track window focus from SDL (e.g. focus gained / lost).
2. While **focused**: run the continuous path.
3. While **unfocused**: run the on-demand path (wait + dirty/wake).
4. On focus change: wake immediately so the next frame applies the new path without waiting for the idle timeout.

## Who decides the mode

| Source | Role |
|--------|------|
| **`App_Type` default** | Hint: e.g. `Application` → focused or on-demand, `Game` → continuous. |
| **Settings override** | Optional `settings.kdl` (or equivalent) force continuous / on-demand / focused for demos and debugging. |
| **Runtime API** | App may change mode when entering a live preview, simulation, etc. |

Products differ by **default mode + how often they request frames**, not by forked engines.

## Wake / demand API (engine contract)

Mode = how the process idles. **Demand** = who forces a frame.

Wake is only required when **effective pacing is on-demand**:

| Selected mode | Window focus | Effective pacing | App must wake for ongoing work? |
|---------------|--------------|------------------|---------------------------------|
| **Continuous** | any | continuous | No — frames already run every iteration. |
| **Focused** | focused | continuous | No. |
| **Focused** | unfocused | on-demand | Yes — if work should continue in the background. |
| **On-demand** | any | on-demand | Yes. |

Calling `Request_Frame` / `Wake_For` in continuous effective pacing is harmless but unnecessary. Vendor libs never call these APIs; the **app** does after stepping them.

Oni exposes only **push wake** (names illustrative)—no app poll-hook registry:

- `Request_Frame()` — schedule at least one more frame.
- `Wake_For(duration)` / `Wake_Until(deadline)` — keep waking until the deadline (drags, scrubbing, app-driven animation).

One demand path avoids a weaker “ask me later” API that stalls until the idle timeout.

### App layer: wiring vendor libs

Only needed while effective pacing is on-demand. After stepping vendor work in tick/draw, if it is still running → `Request_Frame()` or `Wake_For(...)`. Do **not** put vendor adapters inside `oni/`.

Engine-owned wake sources (no vendor involved; same on-demand rule):

- SDL input and window events
- Resize / DPI / focus changes
- Hot-reload / force reload
- Settings apply / file-watch cooldown (prefer **time-based** cooldown under on-demand; today settings watch is frame-counted)
- Text caret blink, IME, hover transitions as needed by widgets

## When to use which

| Situation | Mode | Notes |
|-----------|------|--------|
| Gameplay, physics, always-live viewport | Continuous | Rarely need wake APIs; keeps running unfocused. |
| Interactive desktop tool in use | Focused | Live while focused; idles in background. |
| Docs site / widget gallery at rest | On-demand | App wakes for route-fade duration (effective pacing is always on-demand). |
| Editor idle, user reading | On-demand or Focused | On-demand always waits; Focused is live only while the window is active. |
| Timeline scrub / graph sim burst | On-demand + `Wake_For`, or temporary continuous | Either works; wake keeps global mode simple. |
| Minimized / zero drawable | N/A | Existing `can_render` already skips present; polling/wait can continue. |

## What not to do

- **Per-`Draw_Space` frame policy** — spaces share one frame; sleep is process-wide.
- **Interaction-only with no wake API under on-demand** — app animations, caret, and settings reload will look frozen.
- **App-only busy-loop hacks** without engine wait/dirty — games and tools need one shared contract.
- **Vendor knowledge in Oni** — no imports, adapters, or special cases for app-layer libs; only the generic push-wake contract.
- **App poll hooks for frame demand** — redundant with push wake and delayed by the idle timeout; do not add a second demand path.

## Relation to the current loop

Today the host loops on `should_run` → `reloader` → `app_update` → `Run_Frame`, which always polls non-blocking and presents when possible (VSync-capped). Frame modes extend that path: continuous preserves current behavior; on-demand adds wait + dirty/wake; focused selects continuous or on-demand from window focus before the same tick/layout/draw/present pipeline.

## Rollout sketch

1. Engine: mode enum (`continuous` / `on_demand` / `focused`), focus tracking, dirty/wake flags, `Request_Frame` / `Wake_For`.
2. `run_frame`: resolve effective pacing from mode + focus; on-demand idle → wait with timeout; then existing frame path.
3. Defaults from `App_Type` + optional settings override.
4. App requests frames only when effective pacing is on-demand and work is still active; convert frame-counted watches (e.g. settings cooldown) to time-based where needed.
