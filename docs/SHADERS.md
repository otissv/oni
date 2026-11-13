# SDL GPU shader backends

Oni embeds SPIR-V for Vulkan, MSL 2.1 source for Metal, and DXIL Shader Model 6.0 for Direct3D 12. SDL chooses a backend at device creation from these three advertised formats. `gpu_load_shader` queries that device's actual formats and selects the matching asset, entrypoint, stage and resource counts. UI, LCD text, general vectors, solid vectors and dual-source probes all use the same registry. There is no runtime translator or Vulkan-only shader path.

SPIR-V and DXIL use `main`; MSL uses `main0`. `scripts/build_shaders.py` owns the registry and generates `gpu_shader_assets.odin`. The engine borrows embedded bytes without allocating, so retained devices after hot reload do not depend on pointers into the old DLL. SDL shader handles are released after pipeline creation, including failure and injected-failure paths. Device property objects are destroyed on every path.

All backends require Oni's patched SDL3 with dual-source blending and indirect first-instance support. See [the SDL build instructions](../third_party/sdl3/README.md). The SDL GPU driver override `SDL_GPU_DRIVER` can request `vulkan`, `metal` or `direct3d12`. An unavailable backend or required feature fails initialization; Oni does not downgrade LCD text or switch shader semantics. Vulkan needs a working Vulkan ICD, Metal needs a compatible Apple GPU/OS, and Direct3D 12 needs a compatible Windows GPU/driver.

## Building

Generated assets and `shaders/compiled.json` belong in version control alongside GLSL. Normal development and production builds verify their source and artifact SHA-256 hashes using Python 3.10 or later. Compilers are needed only when a bundle is missing, corrupt, changed, or explicitly rebuilt. Manual `odin build` bypasses scripts; run the verification command first.

```sh
python3 scripts/build_shaders.py --check
python3 scripts/build_shaders.py
python3 scripts/build_shaders.py --force
```

Rebuilding needs `glslc` and the official [SDL_shadercross CLI](https://github.com/libsdl-org/SDL_shadercross), built with SPIRV-Cross and DXC support. Shadercross's DXIL compilation also needs the [DirectX Shader Compiler libraries](https://github.com/microsoft/DirectXShaderCompiler/releases) available to its dynamic loader. These are build tools, not application dependencies. Set `ONI_GLSLC` and `ONI_SHADERCROSS` to executable paths if they are outside `PATH`; each value names one executable, not a shell command. Use `--force` after upgrading the compiler toolchain, then commit the regenerated assets and completion record together. Generating all formats on a machine with this toolchain lets other target machines consume the checked-in bundle without those tools.

GLSL remains the single shader source. `glslc` generates SPIR-V, then shadercross translates it to MSL and DXIL and reflects its resource counts. SDL's resource binding conventions are preserved by shadercross. The build rejects resource-count changes that do not match the registry, invalid bytecode headers, missing MSL entrypoints, and lost MSL dual-source outputs. Translation uses MSL 2.1 explicitly, with unused binding culling disabled. `shaders/compiled.json` covers the builder, every GLSL source and every output. `.gitattributes` preserves binary artifacts and canonical shader text across Windows checkouts.

Builds serialize with an OS file lock and stage all outputs before publication. Compiler or validation failures preserve the previous complete bundle and delete staging files. The completion record is published last; interruption during publication leaves a bundle that fails verification. Sources changing during compilation also reject publication. Individual shaders compile concurrently; every worker finishes before staging is released.

## Verification

```sh
python3 scripts/test_build_shaders.py
./scripts/test_all.sh --gpu-backend vulkan
./scripts/test_all.sh --gpu-backend metal
./scripts/test_all.sh --gpu-backend direct3d12
```

Run each backend command on its native platform with the patched SDL3 installed. `--gpu-backend` forces the SDL driver, checks the actual selected driver, loads every shader and requires vector MSAA/LCD GPU checks instead of skipping them. The existing readback suites cover UI/LCD blending and vector rendering/composition; package tests keep Odin leak tracking enabled. The Python contracts test stale/missing/corrupt artifacts, all-format generation and reuse, reflection mismatch, invalid compiler outputs, source edits during compilation, and failure cleanup. Shader tests inspect every embedded format and both MSL dual-source outputs even on machines without Metal.

The implementation has passed the Vulkan engine suite on Linux. Native Metal and Direct3D 12 runtime acceptance must be run on their respective platforms before claiming all three backends have passed release validation; successful cross-compilation alone does not establish native rendering correctness.
