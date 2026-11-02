#!/bin/bash
# Fetch the SDK-defined Metaplex Core dependency for local validators.
#   bash scripts/dump-mpl-core.sh [rpc-url]
# Requires Solana CLI and installed npm dependencies.
set -eo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
CORE="$(node --input-type=module -e 'import { MPL_CORE_PROGRAM_ID } from "@metaplex-foundation/mpl-core"; console.log(MPL_CORE_PROGRAM_ID)')"
RPC="${1:-https://api.devnet.solana.com}"
mkdir -p "$ROOT/program/deps"
solana program dump --url "$RPC" "$CORE" "$ROOT/program/deps/mpl_core.so"
echo "dumped: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
solana program show --url "$RPC" "$CORE"
sha256sum "$ROOT/program/deps/mpl_core.so"
