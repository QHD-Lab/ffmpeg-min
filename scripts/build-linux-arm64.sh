#!/usr/bin/env bash
# Fully static linux-arm64 build. Run on Linux aarch64 with gcc, make, pkg-config.
. "$(dirname "$0")/lib.sh"
require_host Linux aarch64 arm64
build linux-arm64 -- --extra-ldflags=-static --enable-pthreads
