#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$ROOT"
source "${ROOT}/odin_collections.sh"

BENCH_FRAMES=1800
BENCH_WARMUP=120
MODE="m2"
ISOLATION="full"
MODE_ARGS=0
for arg in "$@"; do
	if [[ "$arg" != "--smoke" ]]; then MODE_ARGS=$((MODE_ARGS + 1)); fi
	case "$arg" in
		--smoke) BENCH_FRAMES=8; BENCH_WARMUP=2 ;;
		--m8) MODE="m8" ;;
		--all) MODE="all" ;;
		--ui) MODE="ui" ;;
		--transform-only) MODE="m2"; ISOLATION="transform-only" ;;
		--morph-only) MODE="m2"; ISOLATION="morph-only" ;;
		--svg-prepare-only) MODE="m8"; ISOLATION="svg-prepare-only" ;;
		--svg-paint-only) MODE="m8"; ISOLATION="svg-paint-only" ;;
		*) echo "Usage: $0 [--smoke] [--m8 | --all | --ui | --transform-only | --morph-only | --svg-prepare-only | --svg-paint-only]" >&2; exit 2 ;;
	esac
done
if (( MODE_ARGS > 1 )); then
	echo "Select exactly one workload or isolation mode" >&2; exit 2
fi
python3 scripts/vector_benchmark_artifacts.py verify
mkdir -p build/test
run_bench() {
	local test_name="$1"
	local define_extra="${2:-}"
	local started status=0
	started="$(date +%s.%N)"
	odin test . -vet -vet-packages:oni,oni_vector -strict-style -o:speed -disable-assert -keep-executable \
		"${ODIN_COLLECTION_FLAGS[@]}" \
		-define:ODIN_TEST_THREADS=1 \
		-define:ODIN_TEST_TRACK_MEMORY=false \
		-define:ODIN_TEST_FAIL_ON_BAD_MEMORY=false \
		-define:ODIN_TEST_NAMES="${test_name}" \
		-define:ONI_VECTOR_BENCHMARK=true \
		-define:ONI_VECTOR_BENCHMARK_ISOLATION="${ISOLATION}" \
		${define_extra} \
		-define:ONI_VECTOR_BENCHMARK_FRAMES="${BENCH_FRAMES}" \
		-define:ONI_VECTOR_BENCHMARK_WARMUP="${BENCH_WARMUP}" \
		-out:"build/test/vector_benchmark_${test_name##*.}" \
		-extra-linker-flags:"${ONI_SDL3_LINKER_FLAGS}-lfreetype -lharfbuzz" || status=$?
	python3 scripts/vector_benchmark_artifacts.py record "${test_name##*.}" "$status" "$started" --isolation "$ISOLATION"
	return "$status"
}
	case "$MODE" in
	m2) run_bench "oni.vector_dense_scene_benchmark" ;;
	ui) run_bench "oni.vector_ordinary_ui_baseline_benchmark" "-define:ONI_VECTOR_BENCHMARK_BASELINE=true" ;;
	m8)
		status=0
		run_bench "oni.vector_dense_scene_svg_benchmark" "-define:ONI_VECTOR_BENCHMARK_M8=true" || status=1
		if [[ "$ISOLATION" == "full" ]]; then run_bench "oni.vector_composition_dense_benchmark" "-define:ONI_VECTOR_BENCHMARK_COMPOSITION=true" || status=1; fi
		exit "$status"
		;;
	all)
		status=0
		run_bench "oni.vector_dense_scene_benchmark" || status=1
		run_bench "oni.vector_dense_scene_svg_benchmark" "-define:ONI_VECTOR_BENCHMARK_M8=true" || status=1
		run_bench "oni.vector_composition_dense_benchmark" "-define:ONI_VECTOR_BENCHMARK_COMPOSITION=true" || status=1
		run_bench "oni.vector_ordinary_ui_baseline_benchmark" "-define:ONI_VECTOR_BENCHMARK_BASELINE=true" || status=1
		exit "$status"
		;;
esac
