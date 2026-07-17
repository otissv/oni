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

if [[ -z "${ONI_ROOT:-}" ]]; then
	ONI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

ONI_LIBS_DIR="${ONI_ROOT}/libs"

ODIN_COLLECTION_FLAGS=(-collection:libs="${ONI_LIBS_DIR}")
