# Sweep build wrapper around sweep_build.sh.
#
# Usage:
#   make -C <sweep_dir> sweep [CHAMPSIM_ROOT=...] [YAML=...] [OUT=...] [EXE_PREFIX=...] [CONFIG=...] [SWEEP_CONFIGS_DIR=...]
#   make -C <sweep_dir> print-matrix [YAML=...]
#   make -C <sweep_dir> verify [CHAMPSIM_ROOT=...] [OUT=...] [EXE_PREFIX=...]
#   make -C <sweep_dir> clean [CHAMPSIM_ROOT=...] [YAML=...]
#
# CHAMPSIM_ROOT defaults to the Makefile's parent directory, which works
# when the Makefile sits at scripts/Makefile inside a ChampSim checkout.
# Invocations from elsewhere must pass CHAMPSIM_ROOT=<path> explicitly.
#
# CONFIG names the base config. For each YAML entry, sweep_build.sh
# derives a per-entry config under SWEEP_CONFIGS_DIR by copying the
# base config and rewriting executable_name, then runs the worker
# against the per-entry config. SWEEP_CONFIGS_DIR defaults to
# $(CHAMPSIM_ROOT)/_sweep_configs_<yaml-basename>. Override it when
# sharing the staging directory with another tool.

# Suppress 'Entering/Leaving directory' for clean witness output.
MAKEFLAGS += --no-print-directory

SCRIPT_DIR := $(realpath $(dir $(lastword $(MAKEFILE_LIST))))
CHAMPSIM_ROOT ?= $(realpath $(SCRIPT_DIR)/..)

YAML              ?= branch/mpp_cbp2025/ls_matrix.yaml
OUT               ?= bin/mpp
EXE_PREFIX        ?= champsim_gc_mpp
CONFIG            ?= champsim_config.json
SWEEP_CONFIGS_DIR ?=

# Resolve potentially-relative YAML to absolute for python's open().
YAML_ABS := $(if $(filter /%,$(YAML)),$(YAML),$(CHAMPSIM_ROOT)/$(YAML))

.PHONY: sweep clean help verify print-matrix

sweep:
	@CHAMPSIM_ROOT="$(CHAMPSIM_ROOT)" SWEEP_CONFIGS_DIR="$(SWEEP_CONFIGS_DIR)" bash $(SCRIPT_DIR)/sweep_build.sh \
	    "$(YAML)" "$(OUT)" "$(EXE_PREFIX)" "$(CONFIG)"

# Emit one normalized line per sweep entry:
#   <name> <KEY1>=<value1> <KEY2>=<value2> ...
# Format-compatible with the legacy build script's print-matrix output, so the
# two can be diffed directly to detect drift between YAML and script values.
print-matrix:
	@python3 -c 'import yaml, sys; \
data = yaml.safe_load(open(sys.argv[1])); \
[print(entry["name"] + " " + " ".join(f"{k}={v}" for k, v in entry["macros"].items())) for entry in data["sweep"]]' \
	    "$(YAML_ABS)"

# Confirm produced binaries differ. Duplicate md5 across variants means
# CPPFLAGS did not reach the compiler.
verify:
	@echo "== md5sum of binaries in $(CHAMPSIM_ROOT)/$(OUT) =="
	@md5sum $(CHAMPSIM_ROOT)/$(OUT)/$(EXE_PREFIX)_* 2>/dev/null || \
	    { echo "ERROR: no binaries found in $(CHAMPSIM_ROOT)/$(OUT)"; exit 1; }
	@n_unique=$$(md5sum $(CHAMPSIM_ROOT)/$(OUT)/$(EXE_PREFIX)_* | awk '{print $$1}' | sort -u | wc -l); \
	  n_total=$$(ls $(CHAMPSIM_ROOT)/$(OUT)/$(EXE_PREFIX)_* | wc -l); \
	  echo "== $$n_unique unique md5 / $$n_total binaries =="; \
	  [[ "$$n_unique" == "$$n_total" ]] || \
	    { echo "ERROR: duplicate md5 detected, CPPFLAGS may not have propagated"; exit 1; }

clean:
	rm -rf $(CHAMPSIM_ROOT)/_worktrees_$(notdir $(basename $(YAML)))
	rm -rf $(CHAMPSIM_ROOT)/_sweep_configs_$(notdir $(basename $(YAML)))
	@echo "Note: produced binaries in $(OUT) NOT removed. Remove manually if needed."
	@echo "Note: clean only touches the default SWEEP_CONFIGS_DIR. If you passed an explicit one, remove it manually."

help:
	@echo "Targets:"
	@echo "  sweep         build N binaries from YAML matrix (with per-entry config staging)"
	@echo "  print-matrix  emit normalized matrix lines from YAML"
	@echo "  verify        check produced binaries differ in md5"
	@echo "  clean         remove worktrees and per-entry config staging for the given YAML"
	@echo ""
	@echo "Variables:"
	@echo "  CHAMPSIM_ROOT     = $(CHAMPSIM_ROOT)"
	@echo "  YAML              = $(YAML)"
	@echo "  OUT               = $(OUT)"
	@echo "  EXE_PREFIX        = $(EXE_PREFIX)"
	@echo "  CONFIG (base)     = $(CONFIG)"
	@echo "  SWEEP_CONFIGS_DIR = $(if $(SWEEP_CONFIGS_DIR),$(SWEEP_CONFIGS_DIR),(default: $(CHAMPSIM_ROOT)/_sweep_configs_<yaml-basename>))"
