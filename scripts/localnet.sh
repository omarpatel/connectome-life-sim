#!/bin/bash
# Local validator with the built program preloaded at its configured address.
#   bash scripts/localnet.sh [port]
# Foreground; Ctrl-C stops it. Each port has a separate disposable ledger.
# Requires Bash, Node, npm dependencies and Solana CLI on PATH.
set -eo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
PORT="${1:-8899}"
URL="http://127.0.0.1:$PORT"
SO="$ROOT/program/target/deploy/instar.so"
CORE_SO="$ROOT/program/deps/mpl_core.so"
CORE_ID="$(node --input-type=module -e 'import { MPL_CORE_PROGRAM_ID } from "@metaplex-foundation/mpl-core"; console.log(MPL_CORE_PROGRAM_ID)')"
test -f "$SO" || { echo "no $SO: run npm run program:build first" >&2; exit 1; }
test -f "$CORE_SO" || { echo "no $CORE_SO: run bash scripts/dump-mpl-core.sh first" >&2; exit 1; }
PROGRAM_ID="${PROGRAM_ID:-$(node -e 'console.log(require("./services/chain/idl/instar.json").address)')}"
OPERATOR="${INSTAR_OPERATOR_KEYPAIR:-$ROOT/.keys/operator.json}"
mkdir -p "$(dirname "$OPERATOR")"
test -f "$OPERATOR" || solana-keygen new --no-bip39-passphrase -s -o "$OPERATOR" >/dev/null
echo "program:  $PROGRAM_ID"
echo "operator: $(solana-keygen pubkey "$OPERATOR")"
echo "rpc:      $URL"

(
  until solana cluster-version --url "$URL" >/dev/null 2>&1; do sleep 1; done
  solana airdrop 100 "$(solana-keygen pubkey "$OPERATOR")" --url "$URL" >/dev/null
  echo "operator funded: $(solana balance "$OPERATOR" --url "$URL")"
) &

# The program is preloaded as an UPGRADEABLE program with the operator as
# upgrade authority: init_world checks that its signer is that authority, and a
# plain --bpf-program preload would set the authority to the default pubkey.
# Metaplex Core is preloaded at its SDK-defined address for asset CPI calls.
# gossip/faucet/dynamic ports are derived so two validators can coexist on one host.
exec solana-test-validator --reset --quiet \
  --ledger "${INSTAR_LEDGER_DIR:-${TMPDIR:-/tmp}/connectome-life-sim-ledger-$PORT}" \
  --rpc-port "$PORT" \
  --gossip-port "$((PORT + 3000))" \
  --faucet-port "$((PORT + 1000))" \
  --dynamic-port-range "$((PORT + 2000))-$((PORT + 2099))" \
  --bpf-program "$CORE_ID" "$CORE_SO" \
  --upgradeable-program "$PROGRAM_ID" "$SO" "$(solana-keygen pubkey "$OPERATOR")"
