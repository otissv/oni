#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

# shellcheck source=odin_collections.sh
source "${ROOT}/odin_collections.sh"

OUT_DIR="build/test"
ODIN_FLAGS=(-vet -strict-style -debug -keep-executable)
FONT_LIBS=(-extra-linker-flags:"-lfreetype -lharfbuzz")

# Odin's test runner tracking allocator: report leaks and fail the suite on them.
TEST_DEFINES=(
	-define:ODIN_TEST_TRACK_MEMORY=true
	-define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true
)

# Packages with @(test) coverage (friendly names → source paths under repo root).
ALL_PACKAGES=(
	colors
	tengu
	oni
	widgets
)

USE_ASAN=false
USE_VALGRIND=false
REPORT_MEMORY=false
PACKAGES=()

usage() {
	cat <<EOF
Usage: $0 [options] [package...]

Run all (or selected) package tests with debug info and leak detection.

Packages (default: all):
  colors  tengu  oni  widgets

Options:
  --asan              Enable AddressSanitizer (-sanitize:address) and leak detection
  --valgrind          After building, re-run each test binary under Valgrind
  --report-memory     Always print per-test memory usage (even with no leaks)
  -h, --help          Show this help

Always enabled:
  -vet -strict-style -debug -keep-executable
  -define:ODIN_TEST_TRACK_MEMORY=true
  -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true

Binaries are kept under ${OUT_DIR}/ for post-mortem debugging.

Examples:
  $0
  $0 oni
  $0 colors tengu
  $0 --asan oni
  $0 --report-memory --asan
  $0 --valgrind widgets
EOF
}

# Map friendly package names to odin test paths.
package_path() {
	case "$1" in
	colors) echo "libs/colors" ;;
	tengu) echo "libs/tengu" ;;
	oni) echo "." ;;
	widgets) echo "widgets" ;;
	*)
		echo "error: unknown package: $1" >&2
		return 1
		;;
	esac
}

needs_font_libs() {
	case "$1" in
	oni | widgets) return 0 ;;
	*) return 1 ;;
	esac
}

package_out_name() {
	echo "$1"
}

run_package() {
	local pkg="$1"
	local pkg_path
	pkg_path="$(package_path "$pkg")"
	local out_name
	out_name="$(package_out_name "$pkg")"
	local out_path="${OUT_DIR}/${out_name}"
	local -a cmd=(odin test "$pkg_path" "${ODIN_FLAGS[@]}" "${ODIN_COLLECTION_FLAGS[@]}" "${TEST_DEFINES[@]}" -out:"$out_path")

	if needs_font_libs "$pkg"; then
		cmd+=("${FONT_LIBS[@]}")
	fi
	if $USE_ASAN; then
		cmd+=(-sanitize:address)
	fi

	echo "==> Testing ${pkg} (${pkg_path})"
	echo "    ${cmd[*]}"

	# First pass: compile + run with Odin's tracking allocator (and optional ASan).
	# Odin's test runner may exit 0 even when tests fail — parse the summary.
	local log
	log="$(mktemp "${OUT_DIR}/run.XXXXXX.log")"
	set +e
	"${cmd[@]}" >"$log" 2>&1
	local compile_status=$?
	set -e
	cat "$log"
	if ((compile_status != 0)); then
		rm -f "$log"
		return "$compile_status"
	fi
	if grep -Eq 'tests? failed\.|[[:space:]][0-9]+ tests? failed' "$log"; then
		rm -f "$log"
		return 1
	fi
	rm -f "$log"

	if $USE_VALGRIND; then
		if ! command -v valgrind >/dev/null 2>&1; then
			echo "error: --valgrind requested but valgrind is not installed" >&2
			return 1
		fi
		if [[ ! -x "$out_path" ]]; then
			echo "error: expected test binary at ${out_path}" >&2
			return 1
		fi
		echo "==> Valgrind ${pkg} (${out_path})"
		valgrind \
			--leak-check=full \
			--show-leak-kinds=definite,possible \
			--errors-for-leak-kinds=definite \
			--error-exitcode=99 \
			--track-origins=yes \
			--quiet \
			"$out_path"
	fi
}

while (($# > 0)); do
	case "$1" in
	-h | --help)
		usage
		exit 0
		;;
	--asan)
		USE_ASAN=true
		shift
		;;
	--valgrind)
		USE_VALGRIND=true
		shift
		;;
	--report-memory)
		REPORT_MEMORY=true
		shift
		;;
	-*)
		echo "Unknown option: $1" >&2
		usage >&2
		exit 1
		;;
	*)
		PACKAGES+=("$1")
		shift
		;;
	esac
done

if $REPORT_MEMORY; then
	TEST_DEFINES+=(-define:ODIN_TEST_ALWAYS_REPORT_MEMORY=true)
fi

if $USE_ASAN; then
	export ASAN_OPTIONS="${ASAN_OPTIONS:-detect_leaks=1:halt_on_error=0:allocator_may_return_null=1}"
	export LSAN_OPTIONS="${LSAN_OPTIONS:-verbosity=0}"
fi

if ((${#PACKAGES[@]} == 0)); then
	PACKAGES=("${ALL_PACKAGES[@]}")
fi

for pkg in "${PACKAGES[@]}"; do
	found=false
	for known in "${ALL_PACKAGES[@]}"; do
		if [[ "$pkg" == "$known" ]]; then
			found=true
			break
		fi
	done
	if ! $found; then
		echo "Unknown package: ${pkg}" >&2
		echo "Known packages: ${ALL_PACKAGES[*]}" >&2
		exit 1
	fi
done

if ! command -v odin >/dev/null 2>&1; then
	echo "error: odin not found on PATH" >&2
	exit 1
fi

mkdir -p "$OUT_DIR"

failed=()
passed=()

# Serial for ASAN/valgrind (exclusive process / cleaner diagnostics); otherwise run packages concurrently.
if $USE_ASAN || $USE_VALGRIND || ((${#PACKAGES[@]} == 1)); then
	for pkg in "${PACKAGES[@]}"; do
		if run_package "$pkg"; then
			passed+=("$pkg")
			echo ""
		else
			status=$?
			failed+=("$pkg")
			echo ""
			echo "FAILED: ${pkg} (exit ${status})"
			echo ""
		fi
	done
else
	declare -A pids=()
	declare -A statuses=()
	log_dir="$(mktemp -d "${OUT_DIR}/logs.XXXXXX")"

	for pkg in "${PACKAGES[@]}"; do
		out_name="$(package_out_name "$pkg")"
		log_file="${log_dir}/${out_name}.log"
		(
			if run_package "$pkg"; then
				exit 0
			else
				exit $?
			fi
		) >"$log_file" 2>&1 &
		pids["$pkg"]=$!
	done

	for pkg in "${PACKAGES[@]}"; do
		pid="${pids[$pkg]}"
		set +e
		wait "$pid"
		statuses["$pkg"]=$?
		set -e
		out_name="$(package_out_name "$pkg")"
		cat "${log_dir}/${out_name}.log"
		echo ""
		if ((statuses["$pkg"] == 0)); then
			passed+=("$pkg")
		else
			failed+=("$pkg")
			echo "FAILED: ${pkg} (exit ${statuses[$pkg]})"
			echo ""
		fi
	done
	rm -rf "$log_dir"
fi

echo "========================================"
echo "Passed: ${#passed[@]}/${#PACKAGES[@]}"
if ((${#passed[@]} > 0)); then
	echo "  ok: ${passed[*]}"
fi
if ((${#failed[@]} > 0)); then
	echo "  fail: ${failed[*]}"
	echo "Binaries (if kept): ${OUT_DIR}/"
	exit 1
fi
echo "All package tests passed (debug + leak checks)."
echo "Binaries kept under ${OUT_DIR}/"
