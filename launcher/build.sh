#!/bin/zsh
# Build of the single launcher, installed at bin/AppleMCP (stable path) and signed "Apple MCP" (see ../build.sh).
set -e
cd "${0:a:h}"
out=$(swift build -c release 2>&1) || { echo "$out" | grep -E "error:"; echo "build failed"; exit 1 }
mkdir -p ../bin
install -m 755 .build/release/AppleMCP ../bin/AppleMCP
../build.sh --sign ../bin/AppleMCP dev.applemcp.launcher
echo "installed and signed: ${PWD:h}/bin/AppleMCP"
