#!/usr/bin/env bash
# Regenerates test/fixtures with a full distro FFmpeg in a throwaway container.
# The minimal build cannot do this itself: it has no video encoder.
# These are synthetic test patterns only; they are inputs for scripts/smoke.sh.
set -euo pipefail
dir=$(cd "$(dirname "$0")/fixtures" && pwd)
docker run --rm -v "$dir:/out" ubuntu:24.04 bash -c '
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq ffmpeg >/dev/null
cd /out
ff() { ffmpeg -hide_banner -loglevel error -y "$@"; }
ff -f lavfi -i testsrc2=size=320x180:rate=15 -f lavfi -i "sine=frequency=1000:sample_rate=48000" -t 4 \
  -map 0:v -map 1:a -c:v libx264 -profile:v baseline -g 15 -pix_fmt yuv420p -b:v 150k \
  -c:a aac -ac 2 -b:a 64k -movflags +faststart h264-aac.mp4
ff -f lavfi -i "sine=frequency=440:sample_rate=48000" -t 2 -ac 2 -c:a ac3 -b:a 96k ac3.mp4
ff -f lavfi -i "sine=frequency=440:sample_rate=48000" -t 2 -ac 2 -c:a mp2 -b:a 96k mp2.mp4
chown '"$(id -u):$(id -g)"' *'
