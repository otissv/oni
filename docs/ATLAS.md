# Atlas — production work order

Dynamic glyph (+ small UI) atlas for Oni. Large unique textures stay standalone (`Load_Texture`); they never enter this atlas.

Production means the **full** stack below: recovery (evict / repack / grow / overflow), **bindless or multi-texture sampling in one draw**, and **defined parallelism / concurrency** with tests. Shipping overflow that silently splits every batch, or parallel raster that races the packer, is not done.

## Policy

| Rule | Decision |
|------|----------|
| Scope | Glyphs + optional small UI packs only |
| Primary | Single shared atlas (`state.textures.atlas`); overflow sheets allowed under cap |
| On full | 1) evict cold → 2) repack if fragmented → 3) grow if under cap → 4) overflow atlas → 5) soft-fail + structured error |
| Growth | Power-of-two from 2048 → `min(device max, ATLAS_HARD_MAX)` (e.g. 8192); at most once per pressure event / frame |
| Eviction | Frame-stamp residency; never evict current-frame, pinned, or prefetched (until pin expires) |
| Repack | Compacts survivors; rewrites all `Font_Glyph_Entry.region`; bumps atlas `generation` |
| Prefetch | Explicit API + optional locale/UI charset at face load / route change |
| Draw path | Multi-atlas glyphs must draw without per-atlas batch breaks: **multi-texture sampling in one draw** (per-vertex slot into consecutive SDL_GPU samplers; fall back to split batches only when device cannot) |
| Concurrency | Documented ownership: atlas mutate + glyph_cache write on one owner path; FreeType raster workers may run in parallel; no races on shelves, pending uploads, or cache; stress-tested |
| Hitch budget | Evict / repack / grow only on pack failure or explicit compact — never every frame |
| Hot reload | CPU surface + shelves + cache authoritative; GPU rebuild for every live atlas id |

**Invariants (Group A):**

- Shelf `cursor_x` never moves backward except explicit pack rewind or repack that rebuilds shelves.
- Padded `w/h > atlas.width/height` fails in `texture_atlas_alloc` before any shelf open or cursor advance.
- Failed `texture_atlas_pack` upload rewinds new shelves **and** existing shelf cursors.
- `font_atlas_reset` clears shelves/pixels **and** invalidates `glyph_cache` (regions are stale).
- Atlas mutation is single-owner (pack / alloc / rewind / reset / repack / grow); workers must not mutate shelves or cache (see Group G).

**Do not ship grow-only or overflow-only.** Eviction + repack before growth; growth before overflow; overflow ships with multi-texture/bindless draw (or an explicit device capability fallback that is tested).

Current baseline: dynamic shelf packer (`ATLAS_DEFAULT_SIZE` 2048, capped grow + overflow) in `texture.odin`; glyph cache in `font_shaper.odin` / `font.odin`; bounded FreeType raster pool then **serial** pack in `font.odin`; multi-atlas batch path (`tex0`–`tex3` + per-vertex slot) in font draw / `batch.odin` with tested `Fallback_Split`.

---

## Agent prompt groups

Give **one group per agent prompt**. Groups are ordered; later groups assume earlier groups are merged. Within a group, implement all items together and land as one PR (or one coherent change set).

### Group A — Correctness (Phase 0)

**Prompt scope:** Fix packer / reset bugs only. No eviction, grow, bindless, or public API.

1. **Pack rollback** — `texture_atlas_pack` must rewind **existing shelf `cursor_x`**, not only `resize` new shelves (tests already document the leak).
2. **`font_atlas_reset` + glyph cache** — clearing shelves/pixels without invalidating `glyph_cache` leaves stale UVs. Reset must clear or invalidate cache entries that point at that atlas (or clear whole `glyph_cache` on face reload).
3. **Reject oversize before shelf open** — padded `w/h > atlas.width/height` must fail without corrupting shelves.
4. **Invariant docs** — shelf cursor never moves backward except explicit rewind/repack; regions invalid after repack/grow until cache rewrite; **atlas mutation is single-owner** (see Group G).

**Status:** Implemented. Pack rewind restores existing shelf `cursor_x`; oversize reject before shelf open; `font_atlas_reset` clears shelves/pixels and the glyph cache (retires standalones); invariants documented here and on `Atlas_State`.

**Exit:** 
- Existing atlas tests green; new tests for cursor rewind + reset clears/invalidates cache. Run `./oni/scripts/test_all.sh` (texture + font at minimum). 
- There are no backwards compatibilities, legacy or temporary code. Manual memory is cleaned up and uses the correct memory allocator. 
- There are no security issues.

**Files (typical):** `oni/texture.odin`, `oni/font.odin`, `oni/texture_test.odin`, `oni/font_test.odin`.

---

### Group B — Residency + stats (Phase 1)

**Prompt scope:** Bookkeeping only. No behavior change for pack failure yet. Depends on Group A.

1. Extend `Atlas_State`: `generation`, occupancy (`bytes_used` / slot count or shelf fill), tie to engine frame index.
2. Extend `Font_Glyph_Entry` (or parallel map): `last_used_frame`, flags `{Pinned, Prefetched}`, `generation` matching atlas.
3. Stamp `last_used_frame` on successful ensure/draw of a glyph.
4. Update occupancy on pack/alloc.
5. Internal `atlas_stats()` (size, used%, cache count, generation, overflow count, draw-path mode later).

**Status:** Implemented. Occupancy is padded RGBA bytes + `slot_count` on alloc (rewound on pack fail / subtracted on cold evict); `font_atlas_reset` clears occupancy and bumps `generation`; ensure/draw touch `last_used_frame` via `state.ui.frame`; `atlas_stats()` / `Get_Atlas_Stats` report live `overflow_count` and `draw_mode`.

**Exit:** 
- Unit tests for stamp + generation; stats accurate after N packs.
- There are no backwards compatibilities, legacy or temporary code. Manual memory is cleaned up and uses the correct memory allocator. 
- There are no security issues.

**Files (typical):** `oni/texture.odin`, `oni/font_shaper.odin`, `oni/font.odin`, tests.

---

### Group C — Evict + repack (Phases 2–3)

**Prompt scope:** First recovery path when atlas is full. Depends on Group B. Implement eviction and repack **in the same change set** — eviction without reclaim leaves holes.

**Eviction (on alloc would-fail or occupancy threshold):**

1. Collect cold keys: `last_used_frame < frame - N` (N = 2–5) and not `Pinned` / `Prefetched`.
2. Delete from `glyph_cache`.
3. Set `needs_repack` and run compaction (do not punch shelf holes without repack).
4. If not enough cold entries → leave failure for Group D (grow).
5. Flush pending uploads before mutating atlas GPU/CPU.
6. Prefetch pins: prefetched start `Prefetched | Pinned`; clear `Pinned` after T unused frames so prefetch is not immortal.

**Repack:**

1. Snapshot survivors; prefer **re-rasterize from FreeType** over storing bitmaps (workers OK if Group G contracts held — serial pack still required).
2. New empty atlas surface (same size for pure compact).
3. Clear shelves; pack survivors (optional height-desc sort).
4. Rewrite survivor `region` + `generation`; bump atlas `generation`.
5. Replace/rebuild GPU texture; flush uploads.
6. Optional internal `atlas_compact()` for tools/tests.
7. Keep invariant: non-glyph atlas users must be in the survivor list or stay out of the atlas.

**Status:** Implemented. `ATLAS_EVICT_COLD_FRAMES=3`, `ATLAS_PREFETCH_PIN_FRAMES=5` (clears Prefetched|Pinned). Pack-full path: flush → `font_atlas_evict_cold` → `font_atlas_repack` / `atlas_compact` (parallel FreeType re-raster via pool, serial pack, height-desc, same size). Nested recover blocked via `atlas.repacking`. Hitch: only on pack failure or explicit `atlas_compact`.

**Exit:** 
_Fill with unused glyphs → pack new glyph succeeds after evict+repack; current-frame glyphs never disappear mid-frame; survivor UVs draw correctly.

- There are no backwards compatibilities, legacy or temporary code. Manual memory is cleaned up and uses the correct memory allocator. 
- There are no security issues.

---

### Group D — Capped growth (Phase 4)

**Prompt scope:** Grow primary atlas when evict+repack is not enough. Depends on Group C (repack-into-larger).

1. Constants: `ATLAS_DEFAULT_SIZE = 2048`, `ATLAS_HARD_MAX` (e.g. 8192).
2. Probe GPU max 2D texture size at device create; effective max = `min(hard, device)`.
3. On pack failure after eviction attempt: `new_size = min(old * 2, effective_max)`.
4. If `new_size == old` → stop (Group E handles overflow).
5. Repack into `new_size`; update `Atlas_State` dimensions; log once old → new.

**Status:** Implemented. `ATLAS_HARD_MAX=8192`; `gpu_probe_max_2d_texture_size` (CreateGPUTexture power-of-two probe, cached in `textures.max_2d_texture_size`, also from `gpu_init`). Recover: evict+same-size repack → `font_atlas_try_grow` (`min(old*2, effective_max)`, `font_atlas_repack(new_size)`, log old→new). At cap → false for Group E.

**Exit:** 
- Tiny test atlas (e.g. 64) fills → grows → pack succeeds; refuses past hard/device max.
- There are no backwards compatibilities, legacy or temporary code. Manual memory is cleaned up and uses the correct memory allocator. 
- There are no security issues.

---

### Group E — Overflow + bindless / multi-texture draw (Phases 5 + draw opt)

**Prompt scope:** Capped overflow **and** production multi-atlas draw in one change set. Depends on Group D. Overflow without multi-texture/bindless is **not** acceptable as the shipped path.

**Overflow storage:**

1. `primary` + `overflow: [dynamic]Atlas_State` (or `[dynamic]` with index 0 = primary).
2. New packs prefer atlas with free space (primary first).
3. Cap overflow count (e.g. 2–4); then soft-fail.
4. Destroy empty overflow atlases after eviction (`texture_atlas_prune_empty_overflow`).

**Multi-texture sampling (required):**

1. Extend batch / UI text shaders so one draw (or one flush) can sample **multiple atlas textures** — e.g. per-quad texture index into a bound set (SDL_GPU consecutive samplers).
2. Probe device capabilities at GPU init; record `atlas_draw_mode` in stats (`Multi_Texture` / `Fallback_Split` only if hardware cannot). True descriptor-index bindless is out of scope for SDL_GPU here.
3. Font draw must stop assuming `entry.region.texture_id == single_atlas.id` for the fast path; emit texture index + UVs for any live atlas id.
4. Fallback split-batch path only when capability probe fails — must be tested, logged once, and still correct (not silently “TODO”).
5. Nearest vs linear and LCD paths must work with the multi-texture binding model.

**Status:** Implemented. Primary + two capped overflow sheets pack primary-first and soft-fail at the cap; empty unreferenced overflow sheets are destroyed after eviction (`texture_atlas_prune_empty_overflow`). Atlas ownership, generations, occupancy, reset, compaction, shutdown, and GPU rebuild cover every live sheet. SDL_GPU uses four consecutive sampler bindings (`tex0`–`tex3`) with a per-vertex atlas slot for one mixed-atlas segment; pipeline creation selects `Multi_Texture`, while the forced capability fallback selects tested per-texture splits and logs once. Gray/LCD and nearest/linear pipelines share the same multi-sampler binding model.

**Exit:** 
- Tiny max size forces 2+ atlases; mixed-atlas text draws in **one** multi-texture/bindless flush on capable devices; capability fallback covered by test; no corrupt UVs.
- There are no backwards compatibilities, legacy or temporary code. Manual memory is cleaned up and uses the correct memory allocator. 
- There are no security issues.

**Files (typical):** `oni/batch.odin`, `oni/shaders/`, `oni/font.odin`, `oni/draw.odin`, `oni/gpu.odin`, `oni/texture.odin`, tests.

---

### Group F — Prefetch, bypass, failure funnel (Phases 6–7)

**Prompt scope:** App-facing prefetch, oversize bypass, and one pack-failure funnel that calls Groups C–E. Depends on Groups C–E for the full funnel.

**Prefetch + bypass:**

1. `Font_Prefetch_Glyphs` / `Font_Prefetch_Text` — shape → ensure → mark Prefetched.
2. Call-site guidance: face load ASCII/UI charset; locale switch; level HUD strings.
3. If single glyph padded size > atlas max dimension → standalone or skip with structured error; never open a shelf that cannot fit.

**Single funnel** (replace bare `log + return false` in alloc/pack/font raster paths):

```
pack(surface):
  try alloc+upload
  if fail:
    flush uploads
    evict_cold()
    if needs_repack: repack(same size)
    retry
  if fail:
    if can_grow: grow+repack; retry
  if fail:
    if can_overflow: ensure_overflow; pack there
  if fail:
    report structured error; return false
```

**Status:** Implemented. `font_atlas_pack_funnel` is the single C→D→E pack path (`Atlas_Pack_Fail` + `last_pack_fail`); exhaustion uses `error_report`. Padded size above `texture_atlas_effective_max` never opens a shelf — glyphs pack as `.Standalone` textures (retired on atlas reset). `Font_Prefetch_Glyphs` / `Font_Prefetch_Text` (+ `Font_Prefetch_Ascii_Ui`) ensure then mark Prefetched|Pinned. Ensure/draw treat standalone as live without atlas generation.

**Exit:** 
- Stress (many faces/sizes) never leaves shelf/cache corrupt; prefetch cache-hits; oversize does not poison atlas.
- There are no backwards compatibilities, legacy or temporary code. Manual memory is cleaned up and uses the correct memory allocator. 
- There are no security issues.

---

### Group G — Parallelism & concurrency (required)

**Prompt scope:** Production threading model for atlas + fonts. Depends on Group C at minimum; land after E/F so overflow, funnel, and multi-texture paths are covered by the same contracts. May tighten Groups C–F code.

**Ownership (document in code + this file):**

| Resource | Who may read | Who may write |
|----------|--------------|---------------|
| Shelves / atlas CPU surface / generation | owner thread; workers only after snapshot handoff | owner only (pack, evict, repack, grow, reset) |
| `glyph_cache` | owner; workers never mutate | owner only (insert after pack; delete on evict) |
| `pending_uploads` | flush on owner / present path | owner pack/upload only |
| FreeType shared `library` / face | main/owner face ops | workers use **temp** library+face only (existing pattern) |
| Batch / GPU bind tables for atlases | render thread / owner present | update only when not mid-draw |

**Required work:**

1. Codify **single-owner atlas mutation** (assert or mutex). No pack/evict/repack/grow from workers.
2. Keep / harden **parallel FreeType raster → serial pack** for `font_ensure_glyphs` miss sets; join all workers before any shelf mutate.
3. **Parallel re-raster during repack** (survivor bitmaps) with the same temp-face worker model; serial pack into new atlas.
4. Prefetch and ensure share the funnel under the same owner; no concurrent ensure from two threads without a defined lock.
5. Flush pending uploads before any atlas resize/repack; no worker touching surfaces that are in `pending_uploads`.
6. Generation checks: draws/ensure ignore or rebuild entries whose `generation` ≠ atlas `generation`.
7. Bounded worker pool reuse instead of create/destroy per miss burst.
8. Race / stress tests: large miss sets, repack under load, ensure+prefetch sequencing, asan/tsan where available.

**Status:** Implemented. `Texture_State.owner_mutex` (recursive) + `owner_depth` / `raster_workers` enforce single-owner mutation: ensure, prefetch, pack funnel, evict, repack, reset, alloc/rewind/begin-repack/overflow all take the owner lock; debug asserts reject mutate while FreeType workers are live. `Font_Raster_Pool` (bounded `FONT_GLYPH_MAX_WORKERS`) reuses threads + per-worker scratch arenas across bursts; `font_rasterize_jobs` posts work via semaphores, joins via `done_sema`, then serial pack on the owner. Concurrent misuse is `atlas_owner_try_lock` → false while held. Pool drained in `font_shutdown` / `texture_atlas_shutdown`.

**Exit:** 
- Written concurrency contract; parallel raster + parallel repack raster proven; no data races under stress; asan clean for font/texture packages.
- There are no backwards compatibilities, legacy or temporary code. Manual memory is cleaned up and uses the correct memory allocator. 
- There are no security issues.

---

### Group H — Ship harden + API + docs + test matrix (Phases 8–10)

**Prompt scope:** Production exit criteria. Depends on Groups F and G. Closes gaps across recovery, multi-texture draw, and concurrency.

**Memory / hot reload / shutdown:**

1. Grow/repack/overflow frees old surfaces/GPU textures; no leaks.
2. `texture_shutdown` / font shutdown: all atlases + glyph_cache + pending uploads + worker pool.
3. Hot reload: rebuild GPU for **every** live atlas texture id; rebind multi-texture draw tables.
4. `font_atlas_reset` = generation++ + clear shelves + invalidate glyph atlas entries.

**Public API (`api.odin`):**

- `Atlas_Stats` / `Get_Atlas_Stats` (include overflow count + `atlas_draw_mode`)
- `Atlas_Compact` (optional)
- `Font_Prefetch_Text` / `Font_Prefetch_Glyphs`
- Do not expose raw shelf mutators or worker internals

**Docs:** keep this file authoritative; reconcile [ROAD_MAP.md](ROAD_MAP.md) / [APP.md](APP.md) atlas notes with this policy.

**Test matrix:**

| Case | Assert | Coverage |
|------|--------|----------|
| Pack rollback existing shelf | cursor restored | `texture_atlas_pack_rewinds_*` |
| Fill → evict cold → pack | success; hot glyphs kept | `font_atlas_fill_evict_repack_*` |
| Never evict current-frame | stamps protect | `font_atlas_evict_cold_skips_hot_*` |
| Fragmented → repack | used% down; UVs valid | `font_atlas_compact_rewrites_*` |
| Grow 64→128 | size + draws | `font_atlas_grows_when_hot_*` |
| At hard max → overflow | second `texture_id` | overflow pack / funnel tests |
| Mixed-atlas text (capable GPU) | one multi-texture flush | `batch_mixed_atlas_text_uses_one_*` |
| Capability fallback | split path + logged | `batch_mixed_atlas_text_fallback_*` |
| Overflow capped → soft fail | false + error | `texture_atlas_overflow_is_capped_*` |
| Prefetch then ensure | cache hit | `font_prefetch_*` / ensure sequencing |
| Oversize glyph | bypass; atlas unchanged | `font_pack_oversize_bypasses_*` |
| Gray vs LCD | separate keys | font LCD/gray region tests |
| Hot reload after grow/overflow | GPU for every live sheet | `texture_reload_gpu_rebuilds_primary_and_overflow_*` |
| Parallel raster + serial pack | under pressure | `font_parallel_raster_then_serial_pack_*` |
| Parallel repack raster | survivors packed | `font_atlas_repack_parallel_raster_*` |
| Concurrent misuse / owner lock | try_lock denied | `font_atlas_owner_lock_blocks_*` |
| Leak | `test_all.sh` + `--asan` | package suite |

**Status:** Implemented. Public `Get_Atlas_Stats` / `Atlas_Compact` / `Font_Prefetch_*`; shutdown retires standalones, drains the FreeType raster pool, prunes empty overflow, and clears atlas owner bookkeeping. Hot reload rebuilds every live atlas sheet. Road map / APP.md atlas items reconciled to this file.

**Exit (definition of done):**

- Normal UI/game text recovers from “atlas full” without corrupt state
- Working set bounded via eviction
- Spikes handled by capped grow (+ rare overflow)
- Overflow draws via bindless/multi-texture on capable devices (tested fallback otherwise)
- Parallelism/concurrency contracts enforced and stress-tested
- Prefetch covers first-frame locale/HUD
- Oversized assets never enter the shared atlas
- Hot reload + leaks + tests have no known gaps
- Docs match code
- There are no backwards compatibilities, legacy or temporary code. Manual memory is cleaned up and uses the correct memory allocator. 
- There are no security issues.

---

### Group I — Arenas & temporary allocators (audit + implement)

**Prompt scope:** After Groups A–H exist, audit every atlas/font/texture path added or touched by this work order for allocator fit, then **implement** the changes. Depends on Group H (or at least C–G so recovery/concurrency/prefetch code is present to audit).

**Allocator rules (match `AGENTS.md`):**

| Allocator | Use for |
|-----------|---------|
| `context.temp_allocator` | Frame/scratch: miss lists, seen maps, worker arg slices, sort keys, one-shot strings — wiped each frame; do not `delete` |
| Dedicated scratch / op arena | Multi-step ops that outlive a single proc but not the frame or not the whole process (e.g. one repack/grow pass): allocate, use, `free_all` / destroy at end of op |
| `context.allocator` (heap) | Long-lived: `glyph_cache`, shelves, atlas CPU/GPU records, overflow atlas list, pinned prefetch metadata that survives frames |

**Audit checklist (must walk and record findings in the PR):**

1. Evict / repack / grow / overflow funnel — temporary survivor lists, sort buffers, key scratch.
2. Parallel raster + repack workers — per-burst slices/maps; prefer temp or op arena; no heap leak on early join/fail.
3. Prefetch text/glyph expand — shaped glyph scratch, string clones (retain only what must outlive the call).
4. Stats / debug formatting — no heap strings left dangling.
5. Batch / multi-texture draw tables rebuilt each frame or on atlas set change — frame temp vs heap.
6. Hot-reload rebuild paths — no accidental heap growth per reload.
7. Any `make`/`new`/`clone` in atlas/font/texture code without matching `delete`/`free` or arena release.

**Implement:**

1. Move ephemeral allocations to `context.temp_allocator` or a clear **op-scoped arena** (repack/grow/ensure-miss burst).
2. Keep only true long-lived structures on the heap; document ownership + shutdown/`font_atlas_reset` cleanup.
3. Do not store temp-allocator pointers in `glyph_cache`, shelves, or other cross-frame state.
4. Worker threads: pass allocator explicitly or use temp/op arenas that do not race the frame wipe; join before owner frees the arena.
5. Add/adjust tests that stress miss/repack/prefetch and assert no leaks under tracking allocator / `--asan`.

**Status:** Implemented.

**Audit notes (what lives where):**

| Path | Allocator | Notes |
|------|-----------|-------|
| Evict `to_delete`, ensure `missing`/`seen`, repack `survivors`/`jobs`/`primary_keys` | owner `context.temp_allocator` | Single-proc owner ops under lock; no cross-frame pointers stored |
| Parallel chunk/thread slices | owner `context.temp_allocator` | Live only until workers join |
| Worker temp-face `cpath` / MM `coords` | per-worker op arena (`FONT_RASTER_WORKER_SCRATCH` heap backing) | Workers never touch engine frame temp; arena `free_all` on face switch; backing `delete` on all join/fail paths |
| Prefetch shape + id expand | `context.temp_allocator` via `font_shape(..., temp)` | No layout-arena consume; no `delete` of shaped; cache keeps only residency entries |
| Prefetch / ensure shaped adapter for glyph ids | `context.temp_allocator` | |
| `atlas_stats` / batch sampler bind table | stack / no heap strings | Multi-atlas bindings are stack `[ATLAS_SAMPLER_SLOTS]` |
| Shelves, `glyph_cache`, overflow list, pending uploads, path records | heap | Cleared in `font_atlas_reset` / `texture_shutdown` / font shutdown; empty overflow pruned after evict |
| `Font_Raster_Pool` threads + scratch backing | heap (pool lifetime) | Created on first parallel burst; `free_all` scratch per face switch / burst assign; joined + deleted on font/atlas shutdown |
| Hot-reload GPU rebuild | reuses existing record ids | No per-reload scratch growth beyond temp transfers |

**Exit:**

- Written audit notes (what moved where) in the PR description
- No heap use for single-op/frame scratch in atlas/font pack paths
- Op arenas freed on all success and failure paths
- `./oni/scripts/test_all.sh` and `--asan` clean for touched packages
- No backwards-compat shims; correct allocator by design

---

## Dependency graph

```
A (correctness)
 └─ B (residency + stats)
     └─ C (evict + repack)
         └─ D (growth)
             └─ E (overflow + bindless / multi-texture draw)
                 └─ F (prefetch + funnel)
                     └─ G (parallelism & concurrency)
                         └─ H (ship / API / docs / full matrix)
                             └─ I (arenas & temporary allocators)
```

Do not call the work “production atlas” until **E, G, H, and I** are done (multi-texture draw + concurrency + ship matrix + allocator pass). All groups A–I are implemented; this file matches the shipped code.

---

## Suggested git / agent cadence

| Agent prompt | Group | PR title hint |
|--------------|-------|----------------|
| 1 | A | fix atlas pack rollback and reset/cache sync |
| 2 | B | add atlas residency stamps and stats |
| 3 | C | evict cold glyphs and repack atlas |
| 4 | D | capped atlas growth on pressure |
| 5 | E | overflow atlases with bindless/multi-texture draw |
| 6 | F | prefetch, oversize bypass, pack failure funnel |
| 7 | G | atlas parallelism and concurrency contracts |
| 8 | H | atlas public API, hot-reload, docs, asan matrix |
| 9 | I | atlas arenas and temporary allocator pass |

---

## Out of scope

- **Baking offline sprite atlases for game levels** — requires a separate build-time asset pipeline / pack tool, not the runtime dynamic atlas
- Dear ImGui or third-party atlas libraries
- Putting full-resolution photographs / level sheets into the dynamic atlas
