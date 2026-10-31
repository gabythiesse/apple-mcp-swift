#!/bin/zsh
# Lance une sonde AppleScript : concatène le helper as.swift et la sonde, puis swift (args passés à la sonde)
D=${TMPDIR:-/tmp}/notes-sondes; mkdir -p $D
P=$1; shift
cat ${0:A:h}/as.swift ${0:A:h}/$P > $D/main.swift && swift $D/main.swift "$@"
