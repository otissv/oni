#!/usr/bin/env bash
set -euo pipefail
ONI_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ONI_ROOT/odin_collections.sh"
M7_GALLERY_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/oni-vector-gallery.XXXXXXXX")"
trap 'rm -rf -- "$M7_GALLERY_ROOT"' EXIT
ln -s "$ONI_ROOT" "$M7_GALLERY_ROOT/oni"
cp "$ONI_ROOT/templates/vector_gallery.odin" "$M7_GALLERY_ROOT/main.odin"
cp "$ONI_ROOT/fixtures/vector/gallery_test.odin" "$M7_GALLERY_ROOT/main_test.odin"
odin test "$M7_GALLERY_ROOT" -vet -strict-style -debug -sanitize:address \
  "${ODIN_COLLECTION_FLAGS[@]}" \
  -define:ODIN_TEST_TRACK_MEMORY=true -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true \
  -define:ODIN_TEST_THREADS=1 \
  -extra-linker-flags:"${ONI_SDL3_LINKER_FLAGS}-lfreetype -lharfbuzz" \
  -out:"$M7_GALLERY_ROOT/gallery-test"
odin build "$M7_GALLERY_ROOT" -vet -strict-style -o:speed -disable-assert \
  "${ODIN_COLLECTION_FLAGS[@]}" \
  -extra-linker-flags:"${ONI_SDL3_LINKER_FLAGS}-lfreetype -lharfbuzz" \
  -out:"$M7_GALLERY_ROOT/gallery"
if [[ "${1:-}" == "--smoke" ]]; then
  (cd "$M7_GALLERY_ROOT" && ./gallery --smoke)
fi
