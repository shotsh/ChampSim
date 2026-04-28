# Sweep build

Build N ChampSim variants from a YAML matrix of `(name, macros)` entries.

This directory adds a sweep mechanism on top of the standard ChampSim
build. A single-binary build still uses the upstream Makefile flow
(`./config.sh && make`). Use this `scripts/` Makefile only when you want
a set of variant binaries from a macro sweep.

## Prerequisites

Complete the standard ChampSim setup first so that a single-binary build
works:

```bash
./config.sh
make
```

Verify the resulting binary in `bin/` runs as expected. The sweep below
replays the same `./config.sh` plus `make` flow once per entry, so it
cannot succeed if the standard build is broken.

## Quick start

```bash
make -C scripts sweep
```

The `-C scripts` flag is the standard `make` option for "operate in this
subdirectory". The actual logic lives in `scripts/Makefile`,
`scripts/sweep_build.sh`, and `scripts/build_one.sh`.

This reads `branch/mpp_cbp2025/ls_matrix.yaml`, builds one binary per
entry, and writes them to `bin/mpp/champsim_gc_mpp_<name>`. The
`CONFIG` argument names the **base config** (`champsim_config.json` by
default). The driver derives a per-entry config for each YAML entry by
copying the base config and rewriting `executable_name` to
`<EXE_PREFIX>_<name>`. The per-entry configs land under
`_sweep_configs_<yaml-basename>/`.

To override defaults:

```bash
make -C scripts sweep \
    YAML=path/to/sweep.yaml \
    OUT=bin/output_dir \
    EXE_PREFIX=champsim_my \
    CONFIG=path/to/base_config.json
```

`SWEEP_CONFIGS_DIR=...` lets you redirect the per-entry config staging
directory if you want to share it with another tool.

## YAML schema

```yaml
sweep:
  - name: VARIANT1
    macros:
      KEY1: value1
      KEY2: value2
  - name: VARIANT2
    macros: { KEY1: value3, KEY2: value4 }
```

Each entry becomes `-DKEY=value` flags on `CPPFLAGS` for that variant's
build, and the binary is copied to `<OUT>/<EXE_PREFIX>_<name>`.

## How it works

Up front, the driver stages a per-entry config for every YAML entry:

1. Read the base config (`<CONFIG>`).
2. For each entry, deepcopy the base, rewrite `executable_name` to
   `<EXE_PREFIX>_<name>`, and write the result to
   `<SWEEP_CONFIGS_DIR>/<EXE_PREFIX>_<name>.json`.

Then, for each entry, the worker (`scripts/build_one.sh`) is invoked
once:

1. Create or reuse a worktree at `_worktrees_<yaml-basename>/<i>_<name>/`.
2. Symlink `vcpkg_installed` and `vcpkg` from the repo root.
3. Emit a `CONFIG_JSON=<path>` line so post-build verifiers can locate
   the exact (per-entry) config used.
4. Run `./config.sh <per_entry_config>` followed by
   `CPPFLAGS=<flags> make -j`.
5. Copy `<worktree>/bin/<EXE_PREFIX>_<name>` (the worktree's build
   output, named after the rewritten `executable_name`) to
   `<OUT>/<EXE_PREFIX>_<name>`.

Because the rewritten `executable_name` flows through ChampSim's parsed
config and ends up in the build output's name and content (it feeds the
`build_id` ChampSim hashes from the parsed config), every entry produces
a deterministic binary keyed on `(SHA, base config, cppflags, name)`.

## Other targets

```bash
make -C scripts print-matrix YAML=...                       # emit normalized matrix lines
make -C scripts verify       OUT=... EXE_PREFIX=...         # check produced binaries differ in md5
make -C scripts clean        YAML=...                       # remove worktrees + per-entry config staging for that YAML
make -C scripts help                                        # list resolved variables
```

`print-matrix` emits one line per entry of the form

```
<name> <KEY1>=<value1> <KEY2>=<value2> ...
```

which is convenient for diffing against another builder's `print-matrix`
output to confirm the YAML and the script agree on the macro values.

## Requirements

- `python3` with `PyYAML` (used to parse the YAML, stage per-entry
  configs, and read each config's `executable_name`).
- A working ChampSim build tree (see Prerequisites above).

## Available sweep matrices

This repo currently ships two sweep matrices, each living next to its
predictor source:

| YAML | Schema | Notes |
|---|---|---|
| `branch/mpp_cbp2025/ls_matrix.yaml` | 5 macros per LS: `MPP_BUDGET_KB`, `MPP_LOGG`, `MPP_LOGB`, `MPP_BLOOM_M_LOG`, `MPP_MAX_LG_TABLE_SIZE` | Default for `make -C scripts sweep` |
| `branch/tage_sc_cbp2025/ls_matrix.yaml` | 1 macro per LS: `LOGSCALE` (drives all derived knobs at compile time) | Pass via `YAML=...` override |

Both matrices have 7 entries (`LS1`..`LS7`) and rely on `#ifndef`-guarded
defaults in the predictor source so that builds without `-D<MACRO>` still
behave exactly like the upstream single-binary build.

Build the MPP sweep (default):

```bash
make -C scripts sweep
# -> bin/mpp/champsim_gc_mpp_LS{1..7}
```

Build the TAGE-SC sweep:

```bash
make -C scripts sweep \
    YAML=branch/tage_sc_cbp2025/ls_matrix.yaml \
    OUT=bin/tage \
    EXE_PREFIX=champsim_gc_tage_sc \
    CONFIG=path/to/tage_config.json
# -> bin/tage/champsim_gc_tage_sc_LS{1..7}
```

`CONFIG` defaults to `champsim_config.json` (the repo's generic config).
Predictor-specific configs (e.g. a Golden Cove core layout) are not part
of this repo. Pass them via `CONFIG=` if needed.

## Layout

```
scripts/
├── sweep_build.sh    # driver: parses YAML, stages per-entry configs, calls worker
├── build_one.sh      # worker: builds one variant in a worktree
├── Makefile          # convenience wrapper
└── README.md         # this file
```
