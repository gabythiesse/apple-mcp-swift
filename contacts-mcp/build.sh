#!/bin/zsh
# Build release, installation aux chemins stables bin/ContactsMCP (lanceur) et bin/libContactsMCPCore.dylib (logique),
# signature avec l'identité fixe « Apple MCP » (voir ../build.sh) : les autorisations macOS survivent aux builds.
set -e
cd "${0:a:h}"
out=$(swift build -c release 2>&1) || { echo "$out" | grep -E "error:"; echo "build en échec"; exit 1 }
install -m 644 .build/release/libContactsMCPCore.dylib bin/libContactsMCPCore.dylib
../build.sh --signer bin/libContactsMCPCore.dylib
if ! cmp -s .build/release/ContactsMCP bin/.ContactsMCP.source 2>/dev/null; then
  install -m 755 .build/release/ContactsMCP bin/ContactsMCP
  cp .build/release/ContactsMCP bin/.ContactsMCP.source
fi
../build.sh --signer bin/ContactsMCP dev.applemcp.contacts-mcp   # toujours : identité + certificat identiques à chaque build
echo "installé : $PWD/bin/ContactsMCP"
