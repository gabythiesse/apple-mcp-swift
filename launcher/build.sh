#!/bin/zsh
# Build du lanceur unique, installé à bin/AppleMCP (chemin stable), signé « Apple MCP » (voir ../build.sh).
set -e
cd "${0:a:h}"
out=$(swift build -c release 2>&1) || { echo "$out" | grep -E "error:"; echo "build en échec"; exit 1 }
install -m 755 .build/release/AppleMCP ../bin/AppleMCP
../build.sh --signer ../bin/AppleMCP dev.applemcp.mcp
echo "installé et signé : ${PWD:h}/bin/AppleMCP"
