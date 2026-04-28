#!/bin/bash
# Build a single ChampSim variant in a worktree.
#
# Called once per YAML entry by sweep_build.sh. Each invocation runs
# config.sh + make in a per-variant worktree and copies the resulting
# binary out.
#
# --config is a per-entry config: a copy of the base config with the
# executable_name field rewritten to the entry's binary name. The
# worker passes it to ./config.sh and reads executable_name back from
# it to locate the build output. The driver stages the per-entry
# configs before invoking the worker.
#
# Usage:
#   build_one.sh \
#       --name <variant_name> \
#       --config <per_entry_config_json> \
#       --cppflags "<-DKEY=val ...>" \
#       --output <path/to/binary> \
#       --worktree-base <path/to/worktree> \
#       [--config-json-marker]
#
# Exits 0 on success and 1 on any build or copy failure. The worktree is
# left in place so the caller can inspect or reuse it.

set -euo pipefail

NAME=""
CONFIG=""
CPPFLAGS_ARG=""
OUTPUT=""
WORKTREE_BASE=""
EMIT_CONFIG_MARKER=0

while (( $# > 0 )); do
    case "$1" in
        --name)
            NAME="$2"
            shift 2
            ;;
        --config)
            CONFIG="$2"
            shift 2
            ;;
        --cppflags)
            CPPFLAGS_ARG="$2"
            shift 2
            ;;
        --output)
            OUTPUT="$2"
            shift 2
            ;;
        --worktree-base)
            WORKTREE_BASE="$2"
            shift 2
            ;;
        --config-json-marker)
            EMIT_CONFIG_MARKER=1
            shift 1
            ;;
        -h|--help)
            sed -n '2,18p' "$0"
            exit 0
            ;;
        *)
            echo "[FAIL] build_one: unknown argument: $1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$NAME" || -z "$CONFIG" || -z "$OUTPUT" || -z "$WORKTREE_BASE" ]]; then
    echo "[FAIL] build_one: --name, --config, --output, --worktree-base are required" >&2
    exit 1
fi

if [[ ! -f "$CONFIG" ]]; then
    echo "[FAIL] build_one ($NAME): config file not found: $CONFIG" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Honour a caller-supplied CHAMPSIM_ROOT. The script-dir parent fallback
# only matches when this script lives at scripts/build_one.sh inside the
# ChampSim tree; in any other layout, the caller must export the path.
CHAMPSIM_ROOT="${CHAMPSIM_ROOT:-$(dirname "${SCRIPT_DIR}")}"
NPROC="${NPROC:-$(nproc 2>/dev/null || echo 8)}"

if [[ ! -d "$WORKTREE_BASE" ]]; then
    git -C "$CHAMPSIM_ROOT" worktree add --detach "$WORKTREE_BASE" HEAD 2>&1 | tail -1
fi

if [[ ! -e "${WORKTREE_BASE}/vcpkg_installed" ]]; then
    ln -s "${CHAMPSIM_ROOT}/vcpkg_installed" "${WORKTREE_BASE}/vcpkg_installed"
fi
if [[ ! -e "${WORKTREE_BASE}/vcpkg" ]]; then
    ln -s "${CHAMPSIM_ROOT}/vcpkg" "${WORKTREE_BASE}/vcpkg"
fi

if (( EMIT_CONFIG_MARKER == 1 )); then
    echo "CONFIG_JSON=$CONFIG"
fi

if ! (
    cd "$WORKTREE_BASE" && \
    ./config.sh "$CONFIG" 2>&1 | tail -3 && \
    CPPFLAGS="$CPPFLAGS_ARG" make -j"$NPROC" 2>&1 | tail -5
); then
    echo "[FAIL] build_one ($NAME): build returned non-zero" >&2
    exit 1
fi

EXE_NAME="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('executable_name', 'champsim'))" "$CONFIG")"
SRC_BIN="${WORKTREE_BASE}/bin/${EXE_NAME}"

if [[ ! -x "$SRC_BIN" ]]; then
    echo "[FAIL] build_one ($NAME): expected binary not found: $SRC_BIN" >&2
    exit 1
fi

OUTPUT_DIR="$(dirname "$OUTPUT")"
mkdir -p "$OUTPUT_DIR"
cp "$SRC_BIN" "$OUTPUT"

SIZE_BYTES="$(stat -c %s "$OUTPUT")"
MD5_SHORT="$(md5sum "$OUTPUT" | cut -c1-8)"
echo "[OK] $OUTPUT (${SIZE_BYTES} bytes, md5: ${MD5_SHORT})"
