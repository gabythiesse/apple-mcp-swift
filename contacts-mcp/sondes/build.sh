#!/bin/zsh
# Compile une sonde avec commun.swift et l'Info.plist embarqué (NSContactsUsageDescription), signe ad hoc,
# puis la lance avec un délai maximal (macOS n'a pas `timeout`) : build.sh <délai_s> <sonde.swift> [args…]
t=$1; src=$2; shift 2
cd "${0:a:h}"
mkdir -p .bin .src/${src%.swift}
out=".bin/${src%.swift}"
cp "$src" .src/${src%.swift}/main.swift
extra=(commun.swift)
swiftc -O -o "$out" .src/${src%.swift}/main.swift $extra \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker ../Info.plist 2>&1 | grep -E "error" && exit 1
codesign --force -s - "$out" 2>/dev/null
perl -e 'alarm shift; exec @ARGV' "$t" "$out" "$@"
