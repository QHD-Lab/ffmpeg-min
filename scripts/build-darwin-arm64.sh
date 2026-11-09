#!/usr/bin/env bash
# macOS arm64 build: libopus linked statically, system libraries dynamically.
# Run on an Apple silicon Mac with Xcode command line tools and pkg-config.
. "$(dirname "$0")/lib.sh"
require_host Darwin arm64
export MACOSX_DEPLOYMENT_TARGET=11.0
build darwin-arm64 -- --cc=clang --enable-pthreads
