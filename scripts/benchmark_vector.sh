#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$ROOT"
source "${ROOT}/odin_collections.sh"

BENCH_FRAMES=1800
BENCH_WARMUP=120
MODE="m2"
if [[ "${1:-}" == "--smoke" && "$#" -eq 1 ]]; then
	BENCH_FRAMES=8
	BENCH_WARMUP=2
elif [[ "${1:-}" == "--m8" ]]; then
	MODE="m8"
elif [[ "${1:-}" == "--all" ]]; then
	MODE="all"
elif [[ "$#" -ne 0 ]]; then
	echo "Usage: $0 [--smoke | --m8 | --all]" >&2
	exit 2
fi
mkdir -p build/test
run_bench() {
	local test_name="$1"
	local define_extra="${2:-}"
	odin test . -vet -vet-packages:oni,oni_vector -strict-style -o:speed -keep-executable \
		"${ODIN_COLLECTION_FLAGS[@]}" \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODIN_TEST_TRACK_MEMORY=false \
		-define:ODIN_TEST_FAIL_ON_BAD_MEMORY=false \
		-define:ODIN_TEST_NAMES="${test_name}" \
		-define:ONI_VECTOR_BENCHMARK=true \
		${define_extra} \
		-define:ONI_VECTOR_BENCHMARK_FRAMES="${BENCH_FRAMES}" \
		-define:ONI_VECTOR_BENCHMARK_WARMUP="${BENCH_WARMUP}" \
		-out:"build/test/vector_benchmark_${test_name##*.}" \
		-extra-linker-flags:"${ONI_SDL3_LINKER_FLAGS}-lfreetype -lharfbuzz"
}
	case "$MODE" in
	m2) run_bench "oni.vector_dense_scene_benchmark" ;;
	m8)
		run_bench "oni.vector_dense_scene_svg_benchmark" "-define:ONI_VECTOR_BENCHMARK_M8=true"
		run_bench "oni.vector_composition_dense_benchmark" "-define:ONI_VECTOR_BENCHMARK_COMPOSITION=true"
		;;
	all)
		run_bench "oni.vector_dense_scene_benchmark"
		run_bench "oni.vector_dense_scene_svg_benchmark" "-define:ONI_VECTOR_BENCHMARK_M8=true"
		run_bench "oni.vector_composition_dense_benchmark" "-define:ONI_VECTOR_BENCHMARK_COMPOSITION=true"
		run_bench "oni.vector_ordinary_ui_baseline_benchmark" "-define:ONI_VECTOR_BENCHMARK_BASELINE=true"
		;;
esac
