#!/bin/zsh
# Release build, installed at the stable paths bin/ContactsMCP (launcher) and bin/libContactsMCPCore.dylib (logic),
# signed with the fixed "Apple MCP" identity (see ../build.sh): macOS permissions survive rebuilds.
set -e
cd "${0:a:h}"
out=$(swift build -c release 2>&1) || { echo "$out" | grep -E "error:"; echo "build failed"; exit 1 }
mkdir -p bin
install -m 644 .build/release/libContactsMCPCore.dylib bin/libContactsMCPCore.dylib
../build.sh --sign bin/libContactsMCPCore.dylib
if ! cmp -s .build/release/ContactsMCP bin/.ContactsMCP.source 2>/dev/null; then
  install -m 755 .build/release/ContactsMCP bin/ContactsMCP
  cp .build/release/ContactsMCP bin/.ContactsMCP.source
fi
../build.sh --sign bin/ContactsMCP dev.applemcp.contacts-mcp   # always: same identity + certificate on every build
echo "installed: $PWD/bin/ContactsMCP"
