# Learn how to build a high level render with SDL£


## Overview
For a general renderer for **2D games + desktop UI + editor/tools**, learn in this order: 
1. **SDL3 basics**  
2. **SDL_Renderer as a beginner-friendly high-level drawing API**  
3. **SDL_GPU as your real backend**  
4. **2D collision & movement** — AABB, platforms, walls, climb, ceiling cling (playable game checkpoint)  
5. **Coordinate spaces** — viewports, camera, and clipping  
6. **Renderer systems** like batching, text, atlases, render targets, and UI/vector drawing.  
7. **Enemies & NPCs** — entity AI, combat, and a full playable game loop (before text and audio polish).  
8. **Custom UI & widgets** — build panels, buttons, text, images, dropdowns, selects, and lists on your own renderer (no Dear ImGui or other GUI libraries).  
9. **Audio** — SDL3_mixer for decode, mix, and playback (parallel to graphics; not tied to SDL_GPU).
10. **Oni production gaps** — Section 13 checklist for unfinished engine/demo shipping work (half-wired styles, form widgets, SPIR-V/debug GPU, hot-reload demo state, tests/CI).



## 1. Odin + SDL3 basics first, no custom GPU yet

  Use Odin’s official vendor package oni_docs so you know what you are importing; Odin lists `vendor:sdl3`, `vendor:sdl3/image`, and `vendor:sdl3/ttf`. 

  Focus on:
  - [ * ]  Opening a window and basic SDL render + vsync
  - [ * ]  event loop
  - [ * ]  keyboard/mouse input
  - [ * ]  timing
  - [ * ]  resize
  - [ * ]  cleanup. 

  Resources: 
  - Odin vendor package list
  - Odin examples repo
  - Odin forum SDL3 “Hellope” example, which shows SDL3 initialization, event handling, drawing, debug text, FPS limiting, and VSync. 

  ([Odin vendor packages](https://pkg.odin-lang.org/vendor/))

## 2. Learn SDL3 from official examples before tutorials full of code

The SDL wiki says the best simple SDL3 tutorials are currently `examples.libsdl.org`; focus only on these sections first: 
- [ * ] **Renderer**, 
- [ * ] **keyboard**
- [ * ] **mouse**
- [ * ] **gamepad**
- [   ] **audio**

([SDL Wiki](https://wiki.libsdl.org/SDL3/Tutorials))


## 3. Use SDL_Renderer briefly as the “model” of a high-level renderer

This is not your final backend, but it teaches the API shape you want: 
- [ * ] `draw_rect`,
- [ * ] `draw_texture`
- [   ] `draw_geometry`
- [ *  ] presentation. 


Use the SDL3 renderer examples and the [Odin SDL3 basic setup](https://github.com/simon-robertson/odin-sdl3-basic-setup) repo.  

Focus on how a simple renderer is created, how events are handled, and how textures/shapes are drawn, not on memorizing C syntax.

## 4. Then move to SDL_GPU in Odin

Use Nadako’s **Odin SDL3 GPU Tutorial** playlist as your main Odin-first GPU resource; 
Focus on:
- [   ] Part 1 “Basic Setup, A Red Triangle”
- [   ] Part 4 “Indexed Drawing, A Quad”
- [   ] Part 5 “Texture Sampling”, 

Skip the 3D-heavy episodes at first because you want a 2D/UI/tool renderer, not a 3D engine. 

([Odin SDL3 GPU Tutorial](https://www.youtube.com/playlist?list=PLI3kBEQ3yd-CbQfRchF70BPLF9G1HEzhy))

## 5. Use C/C++ SDL_GPU resources only for concepts, not as your main path

The best non-Odin beginner resource is **GPUForBeginners**, because it starts from blank window and first triangle using SDL3’s GPU API. 

Use it to understand words like command buffer, swapchain, pipeline, texture, sampler, and render pass. 

Also keep SDL’s official GPU docs open because SDL_GPU targets broad hardware support and is designed so apps usually do not need lots of feature-branching. 

- [   ] GPUForBeginners

([GPUForBeginners](https://gpuforbeginners.com/))

## 6. 2D collision & movement — make the game playable first

You already have a window, input, timing, and rects on screen — now turn that into a **playable side-scroller** with solid feel.

Keep collision in **world/logical coordinates** (same space as your player and level geometry). Do not wait for cameras, batching, or SDL_GPU; `SDL_RenderFillRect` is enough.

Your project already has the starting points:
- `game/structure.odin` — `Platform`, `Wall`, and render helpers
- `game/player.odin` — gravity, jump, platform landing (`player_resolve_platform_landing`)
- `game/game.odin` — fixed timestep, input, host/game split

Build in this order so each step is testable in the running game.

### 6.1 AABB overlap — the foundation

Every solid in this plan starts as an axis-aligned box (`x`, `y`, `w`, `h`).

Focus on:
- [   ] **Overlap test** — two rects intersect when they overlap on both X and Y
- [   ] **Separation on one axis** — if X overlaps but Y does not, they are not colliding (and vice versa)
- [   ] **Penetration depth** — how far one box sits inside another; pick the **smallest** axis to resolve (classic AABB resolution)
- [   ] **Entity vs static** — player moves; platforms/walls stay fixed
- [   ] **Debug draw** — tint overlapping rects or log contact side (top/bottom/left/right)

Mini demo: drag the player with the mouse; print which platform index overlaps.

Resources:
- Your `player_overlaps_platform_x` in `game/player.odin` — already half of an AABB test
- [Metanet N tutorial — Advanced Collision Detection](https://www.metanetsoftware.com/technique/tutorialA.html) — swept AABB and multi-axis resolution (read 6.1–6.2 first; return for 6.6)

### 6.2 Jumping on platforms — vertical resolution

You already land on platforms from above. Harden this before adding walls.

Focus on:
- [ * ] **Feet vs platform top** — resolve when falling through (`player_landing_on_platform`)
- [ * ] **Snap to top** — set `player.y` so feet sit on platform surface
- [ * ] **Ground state** — `on_ground`, jump buffer, coyote time (optional polish)
- [ * ] **Double jump** — `jumps_remaining`, reset on landing
- [   ] **One-way platforms** — pass through from below; only collide when falling
- [   ] **Moving platforms** — add platform velocity to player when standing on it

Mini demo: stack three platforms; jump up through a one-way platform, land on the one above.

### 6.3 Walking into walls — horizontal resolution

`Wall` rects exist in `game/structure.odin` but do not block movement yet. Add **left/right resolution** after vertical platform landing.

Focus on:
- [   ] **Resolve X before Y** (or Y before X — pick one order and stay consistent; try X-first for platformers)
- [   ] **Wall contact from the side** — stop horizontal velocity; nudge player out by penetration depth on X
- [   ] **Corner cases** — landing on a platform edge while pressed into a wall; head bonk on ceiling (short ceiling rects)
- [   ] **Slope teaser** — AABB on slopes needs extra math; defer to 6.6 or use stair-step walls made of small rects

Mini demo: corridor of `Wall` rects; player cannot pass through but can jump over low walls.

### 6.4 Climbing walls — wall cling & vertical crawl

Once horizontal walls work, add **wall state** separate from ground.

Focus on:
- [   ] **Wall detect** — overlapping a wall on left or right while airborne and not on ground
- [   ] **Wall cling** — zero or reduced gravity while holding toward the wall; optional slide speed cap
- [   ] **Wall jump** — push away from wall + upward impulse; consume cling until landing
- [   ] **Climb input** — up/down along the wall surface while clinging (adjust Y with clamp to wall height)
- [   ] **Timer or stamina** — optional limit so cling is not infinite

Mini demo: tall vertical shaft; jump in, cling, climb up, wall-jump to the next ledge.

### 6.5 Clinging to the ceiling — inverted gravity zone

Ceiling cling is the same AABB machinery with **contact from below** and flipped movement feel.

Focus on:
- [   ] **Ceiling detect** — head overlaps ceiling rect while moving up or after a jump into it
- [   ] **Ceiling cling** — flip gravity off; stick `player.y` so head sits under the ceiling surface
- [   ] **Ceiling crawl** — left/right along the ceiling; drop on jump or down input
- [   ] **Transitions** — ceiling → wall (corner), ceiling → fall, wall → ceiling (mantle at top edge)
- [   ] **Separate type or flag** — `Ceiling` vs `Wall`, or one `Solid` with `surface: enum { Floor, Wall, Ceiling }`

Mini demo: room with a ceiling bar; jump up, cling, crawl, drop onto a platform below.

### 6.6 Beyond AABB — when boxes are not enough

Stay on AABB until 6.2–6.5 feel good. Then know what comes next without blocking the playable game.

Focus on (later, not required for first playable build):
- [   ] **Swept AABB** — test motion from `old_pos` to `new_pos` so fast movement does not tunnel through thin walls
- [   ] **Tile/grid collision** — level as a 2D array; broadphase + narrowphase
- [   ] **Circles & capsules** — cheap variation for characters; still axis-aligned broadphase
- [   ] **Rotated rects / polygons** — SAT (separating axis theorem); needed for slopes and arbitrary shapes
- [   ] **Triggers** — overlap without resolution (doors, checkpoints, damage zones)

Resources:
- [Metanet N — Advanced Collision Detection](https://www.metanetsoftware.com/technique/tutorialA.html) — swept tests and tunneling
- [Handmade Hero collision notes](https://handmadehero.org/) — practical entity–tile resolution (concept reference)

### 6.7 Playable game checkpoint

Before Section 7 (viewports & camera), you should be able to play this in your hot-reload build:

- [   ] Move left/right, jump (and double jump)
- [   ] Land on platforms without sinking or jitter
- [   ] Blocked by walls; optional low walls to jump over
- [   ] Wall cling + climb + wall jump **or** ceiling cling + crawl (at least one vertical special move)
- [   ] Level built from `Platform` / `Wall` / ceiling rects in code (editor comes much later)

Then continue the renderer study path — collision feel stays in the game DLL; rendering backend can swap underneath.

## 7. Viewports, camera & clipping

By now you know how to draw; here you learn **where** drawing goes on screen and **how world coordinates map to pixels**.

Three related ideas — keep them separate:

| Concept | What it is | Who owns it |
|---------|------------|-------------|
| **Viewport** | The screen rectangle that receives drawing; local (0, 0) becomes the top-left of that rectangle | Render API (`SDL_SetRenderViewport`, `SDL_SetGPUViewport`) |
| **Clipping** | A hard boundary — nothing draws outside this rect (relative to the viewport) | Render API (`SDL_SetRenderClipRect`, `SDL_SetGPUScissor`) |
| **Camera** | Where the world is viewed from — position, zoom, follow target, bounds | Your game/renderer code (`world_to_screen`, `screen_to_world`) |

Typical frame order:

1. **Camera** decides the world → screen transform (offset, scale, maybe rotation later).
2. **Viewport** sets which on-screen rectangle gets the result (full window for a game; a panel rect for an editor preview).
3. **Clipping** prevents bleed into chrome (toolbars, scroll panels, property columns).

### 7.1 Viewports & clipping with SDL_Renderer

Learn the SDL3 render-state API first — it is the simplest place to see the concepts without pipelines or uniforms.

Focus on:
- [   ] `SDL_SetRenderViewport` — draw into a sub-rectangle; top-left of that rect becomes (0, 0)
- [   ] `SDL_SetRenderClipRect` — clip relative to the current viewport; pass `nil` to disable
- [   ] `SDL_GetRenderViewport` / `SDL_GetRenderClipRect` — inspect current state when debugging
- [   ] Per-target state — each render target has its own viewport and clip rect
- [   ] Mini demo: game content in a central box, static UI chrome drawn outside it

Resources:
- [SDL_SetRenderViewport](https://wiki.libsdl.org/SDL3/SDL_SetRenderViewport)
- [SDL_SetRenderClipRect](https://wiki.libsdl.org/SDL3/SDL_SetRenderClipRect)
- [SDL3 Renderer examples](https://examples.libsdl.org/SDL3/renderer/) — run the official samples; look for viewport/clip usage in source
- [Odin SDL3 basic setup](https://github.com/simon-robertson/odin-sdl3-basic-setup) — extend your rect/texture demo with a panel layout

### 7.2 2D camera — world space vs screen space

A camera is **not** an SDL function. It is a small struct plus conversion helpers you apply before (or inside) draw calls.

Focus on:
- [   ] World coordinates — entity positions live here (your player at x=500, platforms at x=1300)
- [   ] Screen coordinates — pixels in the current viewport
- [   ] `world_to_screen` / `screen_to_world` — mouse picking, debug overlays, editor gizmos
- [   ] Camera position + zoom — subtract camera origin, multiply by zoom (matrix form comes later)
- [   ] Follow target — smooth or hard follow on the player
- [   ] Bounds — clamp camera so you do not show empty void outside the level
- [   ] Mini demo: side-scroller camera that follows the player past x=1280

Resources:
- Your current game (`game/player.odin`, `game/structure.odin`) — add camera offset in `render` before drawing world entities
- [SDL3 coordinate system notes](https://wiki.libsdl.org/SDL3/CategoryRender) — confirm Y-down, pixel units, high-DPI window behavior with `WINDOW_HIGH_PIXEL_DENSITY`

### 7.3 Same concepts on SDL_GPU

When you move to your real backend, the names change but the jobs do not.

Focus on:
- [   ] `SDL_SetGPUViewport` inside a render pass — maps normalized or pixel viewport to the current target
- [   ] `SDL_SetGPUScissor` — GPU scissor rect; same role as clip rect on the renderer
- [   ] Default viewport/scissor — `SDL_BeginGPURenderPass` sets defaults; override per draw as needed
- [   ] Camera as uniform or vertex offset — push camera x/y/zoom once per frame instead of per sprite
- [   ] Editor viewport — render world into an off-screen target, then blit into a UI panel with its own clip

Resources:
- [SDL_gpu.h](https://github.com/libsdl-org/SDL/blob/main/include/SDL3/SDL_gpu.h) — read the render-pass flow and `SDL_GPUViewport` / scissor sections in the header comments
- [SDL_BeginGPURenderPass](https://wiki.libsdl.org/SDL3/SDL_BeginGPURenderPass)
- [Getting started with SDL3_gpu](https://glusoft.com/sdl3-tutorials/getting-started-sdl3_gpu/) — render-pass lifecycle context
- Nadako playlist Part 4–5 — quads and textures are the draw path your camera transform plugs into

### 7.4 Two use cases in this plan

**Game camera (Layer 3):** one viewport = full window; camera scrolls the world.

**Editor viewport (Layer 4):** viewport = panel rect; clip = panel bounds; camera = pan/zoom inside the preview. Same math, different rectangle.

Do not merge UI screen-space drawing with world-space drawing in one pass without resetting viewport/clip between them.

### 7.5 Draw order & z-index — players, NPCs & structures

Once the camera scrolls the world, overlapping sprites expose **draw order** bugs: the player walks in front of a wall that should occlude them, or an NPC draws on top when they should stand behind.

Your current `render` in `game/game.odin` uses a **fixed pass order** — platforms, walls, then player. That works for a flat debug level but breaks as soon as entities share the same vertical band or structures need foreground/background layers.

Three related ideas — keep them separate:

| Concept | What it is | Who owns it |
|---------|------------|-------------|
| **Layer** | Fixed band — background, world solids, entities, foreground, UI | Level data or enum on each drawable |
| **Z-index** | Explicit integer sort key within a layer (higher = drawn later = on top) | Per entity, per structure tile, or per sprite |
| **Y-sort** | Dynamic sort by feet/bottom Y so lower-on-screen draws on top | Computed each frame from world position |

Typical side-scroller rule: **sort moving bodies by feet Y** (`entity.y + entity.h`), then break ties with a small z-index bump (player on top of NPC at same Y, etc.).

Build in this order so each step is visible in the running game.

#### 7.5.1 Structure layers — background, midground, foreground

Platforms and walls are not all the same depth. A tree trunk in front of the player is a **foreground structure**; distant hills are **background** and should never cover entities.

Focus on:
- [   ] **Layer enum** — e.g. `Background`, `World`, `Foreground` on `Platform` / `Wall` or a shared `Structure` record
- [   ] **Draw in layer order** — background structures → world solids → entities → foreground structures
- [   ] **Collision vs render** — foreground props may draw on top but still be non-solid (or only block on one axis)
- [   ] **Parallax teaser** — background layer scrolls slower than camera; defer until 7.2 camera feels good
- [   ] **Debug tint** — color-code layers so mis-assigned rects are obvious

Mini demo: one `Wall` rect drawn as foreground (pink) overlapping the player path; player walks behind it when feet Y is above the wall bottom.

Resources:
- Your `structure_render` in `game/structure.odin` — split or tag by layer before drawing
- Section 7.2 camera — apply the same world → screen transform to every layer

#### 7.5.2 Y-sort for players, enemies & NPCs

All moving bodies share one sort bucket. **Lower feet Y draws first** (farther “into” the screen); higher feet Y draws last (closer to the camera).

Focus on:
- [   ] **Sort key** — `sort_y = entity.y + entity.h` (feet), not center Y
- [   ] **Collect drawables** — build a small list each frame: player + every live enemy/NPC
- [   ] **Stable sort** — when two entities share `sort_y`, use secondary key (`z_index`, spawn order, or entity id)
- [   ] **Player priority** — optional `+epsilon` z bump so the player wins ties at the same feet Y
- [   ] **Dead / off-screen** — skip or push to back; do not sort entities you are not drawing

Mini demo: two colored rects on the same platform; walk one past the other — the lower feet should always cover the higher feet.

Resources:
- Your `Entity` in `game/entity.odin` — add `z_index: i32` or derive sort key in one helper
- `player_render` in `game/player.odin` — fold into a generic `entity_render` used after sorting

#### 7.5.3 Z-index overrides & special cases

Y-sort handles most overlap. **Explicit z-index** handles exceptions without breaking the default rule.

Focus on:
- [   ] **Flying / ghost entities** — ignore Y-sort or use a fixed high layer (projectiles, UI markers in world space)
- [   ] **Ceiling cling & wall crawl** — feet Y still works; verify sort when player is above an NPC on a ledge
- [   ] **Large structures** — a tall wall spans many Y values; entities sort against the **feet line**, not the wall top (optional: per-tile Y-sort for tall props later)
- [   ] **Interact prompts** — draw in screen-space or a `ForegroundUI` layer after all world sorts
- [   ] **Editor gizmo** — selected entity draws with outline on top regardless of Y (editor-only z bump)

Mini demo: flying enemy always draws above ground patrols; stomp still uses collision rects, not draw order.

#### 7.5.4 Render pass integration

Replace ad-hoc `structure_render` → `player_render` with one ordered pipeline (still fine to keep separate procs; **call order** is what matters).

Suggested frame order after camera transform is applied:

1. Clear
2. Background structures (no Y-sort)
3. World structures — platforms, walls, midground props (no Y-sort unless you add tall tiles)
4. **Sort and draw entities** — enemies, NPCs, player (Y-sort + z-index tie-break)
5. Foreground structures
6. Debug overlays & triggers (Section 9)
7. Present

Focus on:
- [   ] **`Drawable` or sort entry** — `{ sort_y, z_index, kind, index }` to avoid duplicating position fields
- [   ] **Single camera offset** — sort in **world space**, then convert to screen when drawing
- [   ] **Hot reload** — sort buffers live in `Game_Memory`; no static sort state across reloads
- [   ] **Batching later** — Y-sort is per-frame draw order; texture batching (Section 8) must respect the same sorted list

Mini demo: patrol enemy walks behind an NPC when its feet are higher on screen; walks in front when lower — no manual per-pair hacks.

#### 7.5.5 Checkpoint before Section 9 entities

Before adding patrol AI and combat, you should see correct overlap in the hot-reload build:

- [   ] At least two structures on different render layers (background + foreground)
- [   ] Player and one other entity Y-sort correctly on a shared platform
- [   ] Tie-break or z-index override works for one special case (e.g. player always wins same-Y ties)
- [   ] Render pass order documented in code comments or a small enum — not scattered magic call order

Then Section 9 enemies and NPCs plug into the same sort bucket without redraw bugs.

## 8. Build your renderer in layers

 [   ] **Layer 1**: platform/app with SDL3 (window, input, timing, **SDL3_mixer init** — Section 11).

 [   ] **Layer 2**: low-level backend with SDL_GPU. 

 **Layer 3**: high-level drawing API: 
 
  - [   ] `draw_rect`
  - [   ] `draw_texture`
  - [   ] `draw_sprite`
  - [   ] `draw_text`
  - [   ] `draw_line`
  - [   ] `draw_panel`
  - [   ] `draw_clip_rect`
  - [   ] `draw_render_target`

 **Layer 4**: custom UI & widgets (no third-party GUI library): 
  - [ * ] layout rects — parent/child bounds, padding, hit areas (see Section 7.1 / 7.4)
  - [ * ] `ui_panel`, `ui_label`, `ui_text`, `ui_image`, `ui_button` — draw + hover/pressed states
  - [   ] `ui_select`, `ui_dropdown` — pick one option from a list
  - [   ] scrolling panels — clip rect + content offset (`Overflow.SCROLL` / `AUTO` style fields exist but are unused by layout/draw)
  - [   ] text input — caret, selection, IME, `SDL_StartTextInput` (`input.text_input` buffer exists; no field widget)
  - [   ] lists & asset browser rows — click, scroll, selection
  - [ * ] focus & active widget — one keyboard target at a time
  - [   ] editor chrome — toolbar, property fields, viewport frame (all built from the widgets above)
  - [   ] form widgets — checkbox, slider, progress, tabs, tooltip, menu, dialog/modal
  - [ * ] wire style APIs that resolve but do nothing — `overflow*` scroll offsets still open; `position` / `visibility` / `z_index` / clip / stacking are laid out

  **Layer 5**: production systems
  - [ * ] asset loading (basic; missing broken-image fallback)
  - [ * ] texture atlases (fixed 2048; no growth / eviction / repack)
  - [ * ] font atlas (same atlas limits)
  - [ * ] batching
  - [ * ] hot reload (engine path; demo package globals still violate persistence — see §13)
  - [   ] debug overlay
  - [   ] frame stats
  - [   ] structured error logging (levels / filter; not always-on stderr DEBUG)
  - [   ] RenderDoc captures
  - [   ] release GPU build (no always-`debug` device; multi-backend shaders beyond SPIR-V)
  - [   ] CI — `odin test` + hot-reload build on push

## 9. Enemies & NPCs — full playable game before polish

Collision, camera, and drawing are in place — now populate the world with things that move, react, and give the player goals.

Reuse what you already have:
- `game/entity.odin` — shared `Entity` fields (`x`, `y`, `w`, `h`, `speed`, `velocity_y`)
- `game/player.odin` — player embeds `Entity`; same collision helpers apply to other bodies
- `game/structure.odin` — platforms and walls are the environment every entity resolves against
- Host/game split — enemies live in the game DLL; hot reload must not leak entity state across reloads unless you intend to

Build in this order so each step is testable without dialogue boxes or sound effects.

### 9.1 Entity list & update order

One player is not enough for a game loop. Introduce a small **entity system** before fancy AI.

Focus on:
- [   ] **Entity storage** — fixed array or dynamic list of enemies/NPCs in `Game_Memory`
- [   ] **Update order** — input → player intent → entity AI → integrate velocity → collision resolution → triggers
- [   ] **Render pass** — Y-sort entities and layer structures per Section 7.5; then debug overlays (same camera transform as Section 7)
- [   ] **Spawn from level data** — hard-coded rects or a simple table in code
- [   ] **Remove on death** — swap-and-pop or tombstone flag; avoid dangling indices during iteration

Mini demo: three colored rects patrol the same platforms as the player; no AI yet, just horizontal bounce at wall edges.

### 9.2 World collision for non-player entities

Enemies should respect the same AABB rules as the player (Section 6), without copy-pasting every proc.

Focus on:
- [   ] **Shared collision** — extract or generalize platform landing and wall blocking for any `Entity`
- [   ] **Gravity toggle** — flyers or ghosts skip vertical resolution; ground enemies use the same gravity constant
- [   ] **One-way platforms** — if you added them in 6.2, enemies fall through from below too
- [   ] **Separation from player** — optional push-apart so entities do not stack inside each other
- [   ] **Debug draw** — contact side per entity when stuck or clipping

Mini demo: an enemy walks off a platform edge, falls, lands on a lower platform, and stops at a wall.

### 9.3 Simple enemy AI

Start with **stateless or one-state** behaviors you can see on screen.

Focus on:
- [   ] **Patrol** — move between two X bounds; flip direction at edges or walls
- [   ] **Idle / alert** — stop until the player enters a trigger rect, then switch to chase
- [   ] **Chase** — move toward player X at `speed`; optional max range so enemies give up
- [   ] **Jump on gap** — optional: if patrol hits a ledge, jump (only after basic patrol works)
- [   ] **Facing** — store `facing_left` for later sprite flip; for now tint or stretch the debug rect

Mini demo: two patrol slimes on different platforms; a third chases only when the player enters its zone.

### 9.4 Combat & player interaction

Make failure and success feel real before you add HUD text or hit sounds.

Focus on:
- [   ] **Hitbox vs hurtbox** — attack rect vs vulnerable body rect; reuse AABB overlap from 6.1
- [   ] **Damage** — subtract health or instant kill; invulnerability frames after hit
- [   ] **Knockback** — impulse on X/Y when struck; respect collision so knockback does not tunnel
- [   ] **Stomp** — classic platformer: player feet overlap enemy top while falling → defeat enemy, bounce player up
- [   ] **Contact damage** — side/bottom touch hurts the player unless invuln
- [   ] **Death & respawn** — reset player to spawn point; optional enemy respawn timer

Mini demo: jump on a patrolling enemy to defeat it; touch it from the side and respawn at level start.

### 9.5 NPCs — non-hostile entities

NPCs share the entity machinery but **do not need combat AI**. They set up dialogue and quests later (Section 10).

Focus on:
- [   ] **NPC type or flag** — `hostile: bool` or separate `Enemy` / `NPC` structs embedding `Entity`
- [   ] **Idle behavior** — stand still or slow wander inside a small radius
- [   ] **Interact zone** — trigger rect; when player presses interact and overlaps, set `pending_interaction_id` (no text UI yet — log to console or flash a rect)
- [   ] **Script hooks** — `on_interact(npc_id)` stub you can fill with dialogue later
- [   ] **Blocking vs ghost** — some NPCs are solid; others let the player walk through

Mini demo: one stationary NPC; stand in front, press a key, see a debug message with the NPC id.

### 9.6 Level goals & game state

Tie entities into **win/lose** so the project feels like a game, not a tech demo.

Focus on:
- [   ] **Checkpoints** — trigger volumes that update respawn position
- [   ] **Collectibles** — overlap to pick up; count in `Game_Memory`; optional win when all collected
- [   ] **Exit / door** — trigger when player overlaps and condition met (e.g. all enemies cleared)
- [   ] **Game states** — `Playing`, `Paused`, `GameOver`, `LevelComplete`; host still owns quit, game owns restart
- [   ] **Simple level load** — function that fills platforms, walls, enemies, NPCs from one data block (still code-defined is fine)

Mini demo: defeat or avoid all enemies, touch the exit rect, freeze gameplay and show “level complete” via colored fullscreen tint (no font yet).

### 9.7 Full playable game checkpoint

Before Section 10 (text/UI) and Section 11 (audio), you should be able to play this in your hot-reload build:

- [   ] At least one level with platforms, walls, player spawn, and exit
- [   ] Two enemy types or behaviors (e.g. patrol + chase-on-sight)
- [   ] Stomp or attack defeat; contact damage and respawn
- [   ] One NPC with interact trigger (debug feedback only)
- [   ] Checkpoints or collectibles optional but recommended
- [   ] Camera follows player through the level (Section 7)
- [   ] Entities Y-sort with foreground/background structures (Section 7.5)
- [   ] Stable update order with no entity leaks across hot reload

Then add `draw_text` and SFX — polish layers on top of a game that already plays end to end.

Resources:
- Your `Entity` in `game/entity.odin` — extend, do not fork a second hierarchy
- Section 6 collision — generalize for all moving bodies
- [Handmade Hero entity model](https://handmadehero.org/) — entities as typed records + update functions (concept reference)
- [Metanet N — game feel](https://www.metanetsoftware.com/technique/tutorialA.html) — knockback and invuln timing

## 10. Text and a custom UI system — no existing GUI library

Do **not** use Dear ImGui, Clay, or other off-the-shelf GUI toolkits. Build UI on top of your renderer primitives: rectangles, text, images, clipping, and layers. The editor in Section 12 is assembled from widgets you write yourself.

### 10.1 Text first

Start with `vendor:sdl3/ttf` or a bitmap font so you can build `draw_text` early. Wire it to NPC interact stubs from Section 9.5 (`pending_interaction_id` → dialogue lines) and combat feedback (health, level complete) from Section 9.4–9.6.

Later learn FreeType + HarfBuzz if you need professional text shaping.

Focus on:
- [   ] `vendor:sdl3/ttf` — load font, render glyph atlas or per-frame quads
- [   ] FreeType + HarfBuzz — only when you need shaping beyond SDL_ttf

### 10.2 UI core — layout and input

A small immediate-mode layer is enough: each frame you declare widgets; the system tracks hover, click, and focus.

Focus on:
- [   ] **Screen-space UI pass** — reset viewport/clip; do not mix with world camera (Section 7.4)
- [   ] **Widget rect** — `x`, `y`, `w`, `h`; optional parent for nested layout
- [   ] **Hit test** — mouse in rect; top-most widget wins
- [   ] **Hot/active IDs** — which button is hovered, which field has keyboard focus
- [   ] **Consume input** — clicked widget eats the event so widgets below do not also fire

Mini demo: three stacked buttons; hover tint and click log the button id.

### 10.3 Widgets to build in order

Each widget is draw calls plus a thin behavior proc. Reuse the same rect/hit-test helpers.

Shipped today (demo/engine): Rectangle, Text, Button, Image, Table (+ head/body/foot/row/cell/caption), focus/tab order.

Still missing for production form/editor UIs:
- [   ] **Checkbox / toggle** — bool state, click to flip
- [   ] **Slider** — drag along axis, map position to value
- [   ] **Text field** — editable; `SDL_StartTextInput` / Stop; caret and selection; consume `input.text_input`
- [   ] **Select** — listbox; several options visible, one selected
- [   ] **Dropdown** — combobox; closed row + popup list; clip to screen; draw above siblings
- [   ] **Scroll view** — overflow clip + content offset + wheel + optional scrollbar thumb
- [   ] **List row** — selectable row for asset names or entity ids
- [   ] **Dialog / modal**, **tooltip**, **menu**, **tabs**, **progress**

Also unfinished style/layout behavior (fields resolve in `style.odin`, unused in `layout.odin` / `draw.odin`):
- [   ] **Overflow** — HIDDEN clip, SCROLL/AUTO scroll offset
- [   ] **Position** — RELATIVE / ABSOLUTE / FIXED / STICKY
- [   ] **Visibility** — hide from hit-test and draw
- [ * ] **Z-index** — stacking within a parent (layout `stack_index`)

Mini demo: property panel with one label, one slider, and one text field editing a platform’s `x` position.

### 10.4 Game UI vs editor UI

Same widget code serves both; only layout and data binding differ.

| Use | Examples |
|-----|----------|
| **In-game HUD** | health bar (`ui_panel` + fill), dialogue box (`ui_panel` + `ui_text`), item icon (`ui_image`), pause menu |
| **Editor** | toolbar (`ui_button` row), asset list (`scroll view` + list rows), inspector (`ui_label` + sliders + `ui_text_field` + `ui_dropdown` for enums), viewport frame (Section 7.4) |

Focus on:
- [   ] **Data binding** — widget reads/writes game structs (platform `x`, enemy `speed`, etc.)
- [   ] **Modal vs mode** — editor overlays game view; F1 toggles edit mode without tearing down widgets
- [   ] **Debug overlay** — optional `ui_label` FPS and collision flags using the same system (not a separate library)

### 10.5 Checkpoint before the tiny editor

- [ * ] `draw_text` works in screen space
- [ * ] Button, label, and panel with hover/click
- [   ] One text field or slider that mutates live game data
- [   ] Scroll view or clipped panel (overflow must actually clip/scroll)
- [ * ] No Dear ImGui / Clay / other GUI dependency in the build

Then Section 12’s editor is just more widgets and layout, not a new UI stack.

## 11. Audio & SDL3_mixer

Audio is a **separate app-layer system** from your renderer. You can add it once window, events, and timing work — it does not depend on SDL_Renderer or SDL_GPU.

Odin ships bindings as `vendor:sdl3/mixer` (alongside `vendor:sdl3`). Link against **SDL3** and **SDL3_mixer** on your platform; see the [Odin vendor packages](https://pkg.odin-lang.org/vendor/) list.

**SDL3 core audio vs SDL3_mixer:** SDL3 gives devices, streams, and callbacks (`SDL_OpenAudioDevice`, `SDL_AudioStream`). That is enough for custom engines or procedural audio. For a 2D game, use **SDL3_mixer** first — it decodes WAV/MP3/Ogg (and more), mixes many sources, and handles the hard parts so you can focus on game code.

SDL3_mixer 3.0 is **not** SDL2_mixer — the API was redesigned (`MIX_*` prefix, `MIX_CreateMixerDevice` instead of `Mix_OpenAudio`, multiple mixers, explicit `MIX_LockMixer` / `MIX_UnlockMixer`). Read the [migration guide](https://wiki.libsdl.org/SDL3_mixer/README-migration) if old tutorials confuse you.

### 11.1 Learn from official SDL3_mixer examples first

Work through [examples.libsdl.org/SDL3_mixer](https://examples.libsdl.org/SDL3_mixer/) in order:

**Basics**
- [   ] Load and play a sound
- [   ] Volume and pause
- [   ] Multiple sounds at once

**Advanced** (after basics work)
- [   ] Music / long streams
- [   ] Fades and stopping groups
- [   ] Anything else in the list that matches your game (looping, device selection, etc.)

Run the C examples to learn the API shape; reimplement the same flow in Odin with `vendor:sdl3/mixer`.

### 11.2 What to build in your project

Keep the same **host / game split** as rendering: the host opens the mixer device and owns shutdown; the game requests plays and volume changes through a thin API.

Focus on:
- [   ] `MIX_CreateMixerDevice` — open once at startup; pass `nil` spec when you want the device default (see SDL docs)
- [   ] Load once, play many — cache `MIX_LoadAudio` (or equivalent) handles; do not reload every frame
- [   ] One-shots vs loops — SFX (footsteps, jumps) vs background music / ambient beds
- [   ] Volume — per-track and a master gain; mute toggle for debug
- [   ] Pause / resume — respect app focus (`SDL_EVENT_WINDOW_FOCUS_LOST`) and user settings
- [   ] Cleanup — stop tracks and destroy mixer on quit (mirror your SDL/video teardown order)
- [   ] Hot reload — keep loaded audio handles in the host; game code only stores logical ids or paths, not raw mixer pointers across reloads

Mini demo: play a jump SFX on Space and start/stop looping music on a key toggle.

### 11.3 Resources

- [SDL3_mixer wiki](https://wiki.libsdl.org/SDL3_mixer)
- [SDL3_mixer API index](https://wiki.libsdl.org/SDL3_mixer/CategoryAPI)
- [SDL3_mixer examples](https://examples.libsdl.org/SDL3_mixer/)
- [MIX_CreateMixerDevice](https://wiki.libsdl.org/SDL3_mixer/MIX_CreateMixerDevice)
- Odin: `vendor:sdl3/mixer` in the Odin repo under `vendor/sdl3/mixer`

Skip SDL2_mixer tutorials unless you are willing to translate every call to SDL3_mixer.

## 12. Final project sequence

Make these mini-projects in order: 
- SDL3 window and input viewer; SDL_Renderer rectangle/texture demo
- SDL_GPU red triangle; SDL_GPU quad; textured quad; `draw_sprite`
- **Playable platformer** — platforms, walls, jump, wall/ceiling cling (Section 6)
- Viewport & clip demo — game view in a sub-rect, UI chrome around it (Section 7.1)
- Camera follow / pan-zoom demo — player moves past screen edge (Section 7.2)
- Y-sort & structure layers demo — player passes in front/behind NPCs and foreground walls (Section 7.5)
- Sprite batcher; texture atlas; clipping/scissor demo
- Render-to-texture demo
- **Full playable level** — enemies, NPC interact stub, combat, respawn, exit (Section 9)
- Font rendering demo
- Audio demo — load WAV/OGG, play SFX on input, loop music, volume + mute (Section 11)
- Custom widget library — panel, label, text, image, button, slider, text field, select, dropdown, scroll view (Section 10)
- Tiny level editor built from those widgets — viewport, toolbar, asset list, property panel (no Dear ImGui)
- SVG / paths

## 13. Oni production gaps (codebase scan)

Open work for shipping the toolkit / demo as a production app UI stack. Tengu is stable (`tengu/STABILITY.md`); this section is **Oni + demo only**.

### 13.1 Layout & style — half-wired APIs

Resolved into `Resolved_Widget_Style`; layout/draw consumption:

- [ * ] `overflow` / `overflow_x` / `overflow_y` — clip + hit; scroll offsets / scrollports still open
- [ * ] `position` — RELATIVE / ABSOLUTE / FIXED / STICKY (sticky clamps to clip until scroll offsets exist)
- [ * ] `visibility` — HIDDEN keeps layout (empty paint/hit); NONE removes subtree
- [ * ] `z_index` / `order` — layout paint lists + `stack_index`; draw tags stack only
- [ * ] `pointer_events` — NONE skips hit, still paints
- [ * ] `popover` (`Draw_Space.POPOVER`) — paint/hit above screen and artboard
- [   ] `Dim` extras ignored by resolvers — `grow`, breakpoint flags (`sm`/`md`/`lg`/`xl`) on width/height (and similar padding/border/radius flags)
- [   ] `aspect_ratio` — listed in `attributes.md`, **absent** from `Widget_Style`
- [   ] Flex beyond grow — shrink / basis (full flexbox not required; document or implement)
- [   ] Polish styles not in the model — margin, transform, box-shadow

### 13.2 Input & widgets

- [   ] Text field + IME — `SDL_StartTextInput` / Stop; caret; selection; widget that drains `input.text_input`
- [   ] Scroll system — content offset, wheel binding, scrollbar widget
- [   ] Checkbox, slider, select, dropdown, list row
- [   ] Dialog/modal, tooltip, menu, tabs, progress
- [   ] Gamepad → focus / widget nav (polling exists in `oni/gamepad.odin`; not on `api.odin`, not wired to widgets)
- [   ] Touch, clipboard, file-drop event paths
- [   ] `SetPointerState` — still a no-op stub (`oni/widgets/widget_types.odin`)
- [   ] `Image.alt` / a11y hooks; missing-texture fallback paint
- [   ] `Widget_Config.title` — field unused

### 13.3 GPU, assets, logging

- [   ] Ship backends beyond SPIR-V — `CreateGPUDevice({.SPIRV}, true, …)` and shader packaging are Vulkan/SPIR-V oriented (MSL / DXIL gaps)
- [   ] Release path — drop always-on GPU debug validation; `build_hot_reload.sh` always passes `-debug`
- [   ] Atlas growth / eviction when the fixed 2048 atlas fills (`texture.odin` / `font.odin`)
- [   ] Structured GPU/present errors to the app (not only `eprintln` + skip)
- [   ] Log levels / filtering (`Log_Debug` always prints; warn not on public API)
- [   ] Optional: debug overlay, frame stats, RenderDoc capture helper

### 13.4 Hot reload & demo app

`Persistent` lives in package `app`. Leaf packages (`components`, `routes`, …) cannot import `app` without cycles (`app` → them). `app/globlas/` holds `Global_State` and a rebound `app: ^Global_State` pointer (`g.app = &persistent.app` in `bind()`).

- [ * ] Hot-reload survival for app-local fields — `theme`, `Route`, `image_texture`, `frame_dt` live in `Persistent.app` via `g.Global_State`
- [   ] Wire `Routes.Components` — nav sets it; `#partial switch` has no case → blank main
- [   ] Starter template `oni/templates/app.odin` — empty `app_draw` / commented init is not a usable production template

### 13.5 Tests, CI, docs, cross-platform

- [   ] Engine tests beyond table layout (`oni/layout_test.odin` only) — flex edges, overflow/scroll, text/font/atlas, input/focus, hot-reload migrate, widgets, textures
- [   ] App package tests
- [   ] CI workflow — build + `odin test` (no `.github/` workflows today)
- [   ] Watch/rebuild on Darwin / Windows (`inotify` + `flock` are Linux-centric)
- [   ] Reconcile `attributes.md` with real fields (stale `aspect_ratio`, half-wired overflow/position notes)
- [   ] Oni stability / version contract (mirror Tengu’s `STABILITY.md` if the engine API is meant to be public)

### 13.6 Still on the learning path (not Oni toolkit)

Unchanged open curriculum work — game + audio, not engine HUD gaps:

- [   ] Sections 6–7, 9 — collision, camera, Y-sort, enemies/NPCs (playable game)
- [   ] Section 11 — SDL3_mixer end to end
- [   ] Section 2 audio examples; Section 3 `draw_geometry`; Section 4–5 GPU tutorial study items
