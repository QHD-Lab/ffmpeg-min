#!/usr/bin/env bash
# Fully static linux-amd64 build. Run on Linux x86_64 with gcc, make, pkg-config.
. "$(dirname "$0")/lib.sh"
require_host Linux x86_64
# --disable-x86asm: no nasm needed; audio-only work does not need the hand-written asm.
build linux-amd64 -- --extra-ldflags=-static --enable-pthreads --disable-x86asm
