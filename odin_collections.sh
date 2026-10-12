#!/usr/bin/env bash
# Shared Odin library collection flags for the Oni framework.
#
# ONI_ROOT defaults to the directory containing this script (the framework root).
# Do not use/export ODIN_ROOT here — that name belongs to the Odin compiler.
#
# Usage from a consumer project root:
#   source ./oni/odin_collections.sh
#   odin build . "${ODIN_COLLECTION_FLAGS[@]}"
#   odin build app -build-mode:dll "${ODIN_COLLECTION_FLAGS[@]}" ...
#
# Usage from inside the framework (tests):
#   source ./odin_collections.sh
#   odin test . "${ODIN_COLLECTION_FLAGS[@]}"
#
# When oni/build/sdl3 exists (see third_party/sdl3/build_sdl3.sh), link and load
# that patched SDL3 for dual-source blending.

if [[ -z "${ONI_ROOT:-}" ]]; then
	ONI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

ONI_LIBS_DIR="${ONI_ROOT}/libs"

ODIN_COLLECTION_FLAGS=(-collection:libs="${ONI_LIBS_DIR}")

# Fragment prepended into a single -extra-linker-flags (Odin keeps only the last).
ONI_SDL3_LINKER_FLAGS=""
ONI_SDL3_PREFIX="${ONI_ROOT}/build/sdl3"
if [[ -d "${ONI_SDL3_PREFIX}/lib" ]]; then
	export PKG_CONFIG_PATH="${ONI_SDL3_PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
	export LD_LIBRARY_PATH="${ONI_SDL3_PREFIX}/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
	ONI_SDL3_LINKER_FLAGS="-L${ONI_SDL3_PREFIX}/lib -Wl,-rpath,${ONI_SDL3_PREFIX}/lib "
fi