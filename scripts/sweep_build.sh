#!/bin/bash
# Build N ChampSim variants from a YAML matrix of (name, macros) entries.
#
# Usage:
#   sweep_build.sh <YAML> <OUT_DIR> <EXE_PREFIX> [CONFIG]
#
# CONFIG names the base config. For each YAML entry, the driver stages a
# per-entry config under SWEEP_CONFIGS_DIR (a copy of the base config with
# executable_name rewritten to <EXE_PREFIX>_<entry.name>) and runs
# build_one.sh against that per-entry config. The output is one binary
# named <EXE_PREFIX>_<entry.name> under OUT_DIR.
#
# Strict-mode notes (intentional, do not "fix"):
#   "(( ++var ))" pre-increment is used instead of "(( var++ ))".
#   Post-increment returns the old value, which under set -e aborts when
#   the variable starts at zero.
#   "${#BUILT[@]}" / "${#FAILED[@]}" require their arrays to be declared
#   with "declare -a NAME=()". Without the explicit empty initialiser,
#   set -u treats the length read as an unset reference.
#
# YAML schema:
#   sweep:
#     - name: <variant_name>
#       macros:
#         <KEY>: <value>
#         ...

set -euo pipefail

if (( $# < 3 )); then
    echo "Usage: $0 <YAML> <OUT_DIR> <EXE_PREFIX> [CONFIG]" >&2
    exit 2
fi

YAML="$1"
OUT_DIR="$2"
EXE_PREFIX="$3"
CONFIG_PATH="${4:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHAMPSIM_ROOT="${CHAMPSIM_ROOT:-$(dirname "${SCRIPT_DIR}")}"
# Export so the worker subprocess inherits the same CHAMPSIM_ROOT instead
# of recomputing one from its own SCRIPT_DIR (which can resolve elsewhere
# when the caller invokes this script from outside the ChampSim tree).
export CHAMPSIM_ROOT
WORKER="${SCRIPT_DIR}/build_one.sh"

if [[ -z "$CONFIG_PATH" ]]; then
    CONFIG_PATH="${CHAMPSIM_ROOT}/champsim_config.json"
fi

resolve_path() {
    local p="$1"
    if [[ "${p:0:1}" == "/" ]]; then
        echo "$p"
    else
        echo "${CHAMPSIM_ROOT}/$p"
    fi
}

YAML="$(resolve_path "$YAML")"
OUT_DIR="$(resolve_path "$OUT_DIR")"
CONFIG_PATH="$(resolve_path "$CONFIG_PATH")"

[[ -f "$YAML" ]] || { echo "ERROR: YAML not found: $YAML" >&2; exit 3; }
[[ -f "$CONFIG_PATH" ]] || { echo "ERROR: CONFIG not found: $CONFIG_PATH" >&2; exit 3; }
[[ -x "$WORKER" ]] || { echo "ERROR: worker not executable: $WORKER" >&2; exit 3; }

WORKTREE_BASE="${CHAMPSIM_ROOT}/_worktrees_$(basename "$YAML" .yaml)"
SWEEP_CONFIGS_DIR="${SWEEP_CONFIGS_DIR:-${CHAMPSIM_ROOT}/_sweep_configs_$(basename "$YAML" .yaml)}"

mkdir -p "$OUT_DIR" "$WORKTREE_BASE" "$SWEEP_CONFIGS_DIR"

echo "[sweep_build] YAML              = $YAML"
echo "[sweep_build] OUT_DIR           = $OUT_DIR"
echo "[sweep_build] EXE_PREFIX        = $EXE_PREFIX"
echo "[sweep_build] CONFIG (base)     = $CONFIG_PATH"
echo "[sweep_build] WORKTREE          = $WORKTREE_BASE"
echo "[sweep_build] SWEEP_CONFIGS_DIR = $SWEEP_CONFIGS_DIR"
echo "[sweep_build] WORKER            = $WORKER"
echo

parse_yaml() {
    python3 - "$YAML" <<'PYEOF'
import sys
try:
    import yaml
except ImportError:
    print("ERROR: PyYAML required (pip install pyyaml)", file=sys.stderr)
    sys.exit(4)
with open(sys.argv[1]) as f:
    data = yaml.safe_load(f)
for entry in data.get("sweep", []):
    name = entry["name"]
    macros = entry.get("macros", {})
    flags = " ".join(f"-D{k}={v}" for k, v in macros.items())
    print(f"{name}|{flags}")
PYEOF
}

stage_per_entry_configs() {
    python3 - "$YAML" "$CONFIG_PATH" "$EXE_PREFIX" "$SWEEP_CONFIGS_DIR" <<'PYEOF'
import json
import sys
from copy import deepcopy

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML required (pip install pyyaml)", file=sys.stderr)
    sys.exit(4)

yaml_path, base_config_path, exe_prefix, configs_dir = sys.argv[1:5]

with open(base_config_path) as f:
    base = json.load(f)
with open(yaml_path) as f:
    data = yaml.safe_load(f)

entries = data.get("sweep") if isinstance(data, dict) else None
if not entries:
    print(f"ERROR: no sweep entries in {yaml_path}", file=sys.stderr)
    sys.exit(5)

for entry in entries:
    name = entry["name"]
    binary = f"{exe_prefix}_{name}"
    per_entry = deepcopy(base)
    per_entry["executable_name"] = binary
    out_path = f"{configs_dir}/{binary}.json"
    with open(out_path, "w") as f:
        json.dump(per_entry, f, indent=2)
        f.write("\n")
    print(f"[stage] {out_path}")
PYEOF
}

ENTRIES="$(parse_yaml)"
[[ -n "$ENTRIES" ]] || { echo "ERROR: no entries parsed from $YAML" >&2; exit 5; }

stage_per_entry_configs

i=0
build_count=0
fail_count=0
declare -a BUILT=()
declare -a FAILED=()

while IFS='|' read -r name flags; do
    [[ -n "$name" ]] || continue
    worktree="${WORKTREE_BASE}/${i}_${name}"
    output="${OUT_DIR}/${EXE_PREFIX}_${name}"
    per_entry_config="${SWEEP_CONFIGS_DIR}/${EXE_PREFIX}_${name}.json"
    echo "==== [${i}] Building variant '${name}' ===="
    echo "  flags: ${flags}"
    echo "  worktree: ${worktree}"
    echo "  per-entry config: ${per_entry_config}"

    if "$WORKER" \
            --name "$name" \
            --config "$per_entry_config" \
            --cppflags "$flags" \
            --output "$output" \
            --worktree-base "$worktree" \
            --config-json-marker; then
        BUILT+=("${output}")
        (( ++build_count ))
    else
        FAILED+=("${name}")
        (( ++fail_count ))
    fi

    (( ++i ))
done <<< "$ENTRIES"

echo
echo "==== Sweep build summary ===="
echo "  built : ${build_count}"
echo "  failed: ${fail_count}"
if (( ${#BUILT[@]} > 0 )); then
    echo "  binaries:"
    for b in "${BUILT[@]}"; do
        echo "    $b"
    done
fi
if (( ${#FAILED[@]} > 0 )); then
    echo "  failures:"
    for f in "${FAILED[@]}"; do
        echo "    $f"
    done
    exit 1
fi
