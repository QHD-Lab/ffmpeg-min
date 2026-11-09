#!/usr/bin/env bash
# Fully static linux-amd64 build against musl, so the only LGPL code inside is FFmpeg.
# Run on Linux x86_64 with docker: it builds inside the pinned Alpine image (versions.env).
. "$(dirname "$0")/lib.sh"
require_host Linux x86_64
in_alpine "$0"
build linux-amd64 -- --extra-ldflags=-static --enable-pthreads --disable-x86asm
