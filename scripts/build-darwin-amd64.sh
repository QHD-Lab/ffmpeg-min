#!/usr/bin/env bash
# macOS x86_64 build: libopus linked statically, system libraries dynamically.
# Run on an Intel Mac with Xcode command line tools and pkg-config.
. "$(dirname "$0")/lib.sh"
require_host Darwin x86_64
export MACOSX_DEPLOYMENT_TARGET=11.0
build darwin-amd64 -- --cc=clang --enable-pthreads --disable-x86asm
