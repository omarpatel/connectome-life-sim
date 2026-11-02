#!/bin/bash
# Quick native check of the world engine while developing: compile errors and
# warnings, then the native tests (ci profile), optionally one test by name
# with extra harness args (e.g. --nocapture).
#   bash scripts/check-sim.sh [test-name [harness args...]]
set -eo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/sim"
cargo build --profile ci
cargo test --profile ci -- --test-threads=1 "$@"
