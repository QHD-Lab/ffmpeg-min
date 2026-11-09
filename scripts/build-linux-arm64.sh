#!/usr/bin/env bash
# Fully static linux-arm64 build against musl, so the only LGPL code inside is FFmpeg.
# Run on Linux aarch64 with docker: it builds inside the pinned Alpine image (versions.env).
. "$(dirname "$0")/lib.sh"
require_host Linux aarch64 arm64
in_alpine "$0"
build linux-arm64 -- --extra-ldflags=-static --enable-pthreads
