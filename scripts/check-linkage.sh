#!/usr/bin/env bash
# check-linkage.sh <platform> <binary>: the binary may depend on nothing but the OS.
set -euo pipefail
case $1 in
  linux-*)
    file "$2"
    file "$2" | grep -Eq "statically linked|static-pie linked" ;;
  darwin-*)
    otool -L "$2"
    ! otool -L "$2" | tail -n +2 | grep -vE '^[[:space:]]+/(usr/lib|System/Library)/' ;;
  windows-*)
    dlls=$(x86_64-w64-mingw32-objdump -p "$2" | sed -n 's/.*DLL Name: //p')
    echo "$dlls"
    ! echo "$dlls" | grep -viE '^(kernel32|msvcrt|ws2_32|bcrypt|advapi32|user32|shell32|ole32|api-ms-win-[a-z0-9-]+)\.dll$' ;;
  *) echo "unknown platform $1" >&2; exit 2 ;;
esac
