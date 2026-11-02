#!/bin/bash
# Build the on-chain program and run its test suite against a local validator.
#   bash scripts/build-program.sh [build|test]
# Default is both. `build` produces the deployable artifact (real timers) and
# copies the IDL + TS types to services/chain/idl/ (program/target is
# gitignored, so the runtime never reads from there). `test` rebuilds with the
# short-timers feature so the recovery drills can wait their timers out in
# real time, runs `anchor test`, then restores the real-timer build.
# target/deploy/instar.features records the artifact's compile-time features.
# Failed builds retain a "building:<features>" marker.
set -eo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-all}"
INSTAR_OPERATOR_KEYPAIR="${INSTAR_OPERATOR_KEYPAIR:-$ROOT/.keys/operator.json}"
case "$INSTAR_OPERATOR_KEYPAIR" in
  /*) ;;
  *) INSTAR_OPERATOR_KEYPAIR="$ROOT/$INSTAR_OPERATOR_KEYPAIR" ;;
esac
export INSTAR_OPERATOR_KEYPAIR

cd "$ROOT/program"

# Print a build log without cargo's per-crate noise; keep the exit status.
quiet() {
  local log; log="$(mktemp)"
  if "$@" >"$log" 2>&1; then
    grep -vE "^\s*(Compiling|Finished|Running|warning: unused manifest key)|^\s*$" "$log" || true
    rm -f "$log"
  else
    cat "$log"; rm -f "$log"
    echo "FAILED: $*" >&2
    return 1
  fi
}

build() {
  # $1 = feature list for cargo, or "default".
  # sBPF v3 via cargo build-sbf directly: `anchor build` cannot pass --arch
  # (it forwards extra args to the IDL's cargo test as well). The build-sbf
  # default (v0) cannot be loaded by validators with SIMD-0500 active.
  # The IDL is built separately; it does not depend on either.
  local args=(--arch v3)
  [ "$1" = "default" ] || args+=(--features "$1")
  mkdir -p target/deploy
  echo "building:$1" > target/deploy/instar.features
  quiet cargo build-sbf "${args[@]}"
  quiet anchor idl build -o target/idl/instar.json -t target/types/instar.ts
  test -f target/deploy/instar.so
  echo "$1" > target/deploy/instar.features
}

publish_idl() {
  mkdir -p "$ROOT/services/chain/idl"
  cp target/idl/instar.json "$ROOT/services/chain/idl/instar.json"
  cp target/types/instar.ts "$ROOT/services/chain/idl/instar.ts"
  echo "idl -> services/chain/idl/instar.json (address $(node -e 'console.log(require("./target/idl/instar.json").address)'))"
}

if [ "$MODE" = "build" ] || [ "$MODE" = "all" ]; then
  echo "== anchor build (real timers) =="
  build default
  publish_idl
fi

# The suite runs against our own validator (localnet.sh on port 8999),
# not anchor's: anchor preloads workspace programs with --bpf-program, which
# leaves the upgrade authority unset, and init_world requires its signer to
# BE the upgrade authority. localnet.sh preloads the program as
# upgradeable with the local operator as that authority.
TEST_RPC=http://127.0.0.1:8999
run_suite() {
  bash "$ROOT/scripts/localnet.sh" 8999 &
  local vpid=$!
  trap 'kill $vpid 2>/dev/null; wait $vpid 2>/dev/null' EXIT
  local deadline=$((SECONDS + 120))
  while true; do
    if ! kill -0 "$vpid" 2>/dev/null; then
      echo "localnet exited before readiness; check its output above. If Core is missing, run bash scripts/dump-mpl-core.sh first." >&2
      return 1
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "localnet did not become ready within 120 seconds; check its output above and ensure bash scripts/dump-mpl-core.sh has fetched Core." >&2
      return 1
    fi
    if solana cluster-version --url "$TEST_RPC" >/dev/null 2>&1; then break; fi
    sleep 1
  done
  sleep 2
  anchor test --skip-build --skip-local-validator --skip-deploy --provider.cluster "$TEST_RPC" --provider.wallet "${INSTAR_OPERATOR_KEYPAIR:-$ROOT/.keys/operator.json}"
  kill $vpid 2>/dev/null; wait $vpid 2>/dev/null || true
  trap - EXIT
}

if [ "$MODE" = "retest" ]; then
  # iterate on the TS suite without rebuilding: the artifact on disk must be
  # the short-timers build from a previous `test` run
  test "$(cat target/deploy/instar.features)" = "short-timers" || { echo "artifact is not a short-timers build; run test" >&2; exit 1; }
  run_suite
  exit 0
fi

if [ "$MODE" = "test" ] || [ "$MODE" = "all" ]; then
  if [ ! -d node_modules ]; then
    echo "program/node_modules missing: run 'npm ci' in program/ first" >&2
    exit 1
  fi
  echo "== anchor test (short timers) =="
  build short-timers
  run_suite
  echo "== restore real-timer artifact =="
  build default
  publish_idl
fi

echo PROGRAM_BUILD_OK
