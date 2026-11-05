# Refactor report — 2026-11-03-code-guidelines-e321c0

- **Skill:** code-guidelines
- **Scope:** turn vector performance changes
- **Started:** 2026-11-03T20:04:46.270Z on `main` at `e0f536c332b6`
- **Outcomes:** kept 2, reverted 0, rejected 0, skipped 0, suggested 0, not-applied 0

## Changes

| Id | Where | Guideline | Source | Before → after | Why | Origin | Outcome |
|---|---|---|---|---|---|---|---|
| 1 | vector_gpu.odin:470 | dead-code | agent | `vector_gpu_buffer_hash` → `removed unused hash helper, import and upload hash fields` | contiguous frame uploads no longer use per-buffer hashing | uncommitted (implementer) | kept |
| 2 | vector_gpu.odin:51 | dead-code | agent | `uploaded_geometry_epoch; uploaded_vertex_bytes; uploaded_index_bytes; vertices_d` → `removed write-only residency bookkeeping and resets` | contiguous immutable uploads always refresh frame buffers; stale residency flags no longer control an upload | e0f536c332b6 | kept |
