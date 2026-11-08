#!/usr/bin/env bash
# windows-amd64 build, cross-compiled on Linux with mingw-w64 (x86_64-w64-mingw32-gcc).
# -static also links libgcc and winpthreads in, so the .exe needs only Windows DLLs.
. "$(dirname "$0")/lib.sh"
require_host Linux x86_64 aarch64 arm64
build windows-amd64 --host=x86_64-w64-mingw32 --disable-stack-protector -- \
  --target-os=mingw32 --arch=x86_64 --cross-prefix=x86_64-w64-mingw32- --enable-cross-compile \
  --enable-w32threads --disable-x86asm --extra-ldflags=-static
