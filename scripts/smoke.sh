#!/usr/bin/env bash
# smoke.sh <ffmpeg binary>: checks the license and components, then runs the
# iCrew audio path end to end over RTSP on 127.0.0.1, using only this binary:
#   publish h264-aac.mp4 -> [listen, video copy, AAC -> libopus, publish] -> [listen, check H264 + Opus]
set -euo pipefail
FF=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
cd "$(dirname "$0")/../test/fixtures"
TMP=$(mktemp -d)
trap 'kill $(jobs -p) 2>/dev/null || true' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ff() { "$FF" -hide_banner -nostdin "$@"; }

ff -version | head -1
conf=$(ff -buildconf)
case $conf in *--enable-gpl*|*--enable-nonfree*|*--enable-version3*) fail "non-LGPL configure flag: $conf" ;; esac
ff -L > "$TMP/license"
grep -q "GNU Lesser General Public" "$TMP/license" && grep -q "version 2.1" "$TMP/license" || fail "license is not LGPL 2.1"
echo "ok   license: LGPL 2.1 or later, no gpl/nonfree/version3"

ff -encoders > "$TMP/enc"
encoders=$(sed '1,/------/d' "$TMP/enc" | awk '{print $2}' | tr '\n' ' ')
[ "$encoders" = "libopus " ] || fail "expected only the libopus encoder, got: $encoders"
ff -decoders > "$TMP/dec"
for d in aac aac_latm ac3 eac3 mp1 mp2 mp3; do grep -Eq "^ A[^ ]* +$d " "$TMP/dec" || fail "missing decoder $d"; done
ff -muxers > "$TMP/mux"; ff -demuxers > "$TMP/demux"; ff -protocols > "$TMP/proto"
grep -Eq " rtsp " "$TMP/mux" && grep -Eq " rtsp " "$TMP/demux" || fail "missing rtsp muxer/demuxer"
for p in tcp udp rtp; do grep -Eq "^ +$p$" "$TMP/proto" || fail "missing protocol $p"; done
echo "ok   components: only libopus encoder; aac aac_latm ac3 eac3 mp1 mp2 mp3 decoders; rtsp; tcp udp rtp"

for f in ac3 mp2; do
  ff -i $f.mp4 -c:a libopus -ar 48000 -ac 2 -f null - > "$TMP/$f.log" 2>&1 || { cat "$TMP/$f.log"; fail "$f -> opus"; }
  grep -q -- "-> opus (libopus)" "$TMP/$f.log" || fail "$f was not encoded with libopus"
done
echo "ok   ac3.mp4 and mp2.mp4 -> libopus"

IN=rtsp://127.0.0.1:18554/pgm-in OUT=rtsp://127.0.0.1:18555/pgm-out
ff -rtsp_flags listen -listen_timeout 30 -i $OUT -c copy -f null - > "$TMP/view.log" 2>&1 & view=$!
sleep 2
ff -rtsp_flags listen -listen_timeout 30 -i $IN -map 0:v:0 -map 0:a:0 -c:v copy \
  -c:a libopus -ar 48000 -ac 2 -b:a 96k -application lowdelay -frame_duration 20 \
  -rtsp_transport tcp -f rtsp $OUT > "$TMP/bridge.log" 2>&1 & bridge=$!
sleep 2
ff -re -i h264-aac.mp4 -c copy -rtsp_transport tcp -f rtsp $IN > "$TMP/pub.log" 2>&1 || { cat "$TMP/pub.log"; fail "publish"; }
wait $bridge || { cat "$TMP/bridge.log"; fail "bridge exited with an error"; }
wait $view || { cat "$TMP/view.log"; fail "viewer exited with an error"; }
grep -q "Video: h264" "$TMP/view.log" && grep -q "Audio: opus, 48000 Hz, stereo" "$TMP/view.log" \
  || { cat "$TMP/view.log"; fail "pgm-out is not H264 + Opus"; }
frames=$(grep -o "frame= *[0-9]*" "$TMP/view.log" | tail -1 | tr -dc 0-9)
[ "${frames:-0}" -ge 55 ] || { cat "$TMP/view.log"; fail "pgm-out got only ${frames:-0} of 60 video frames"; }
echo "ok   RTSP: H264+AAC in -> H264 (copy) + Opus 48 kHz stereo out, $frames video frames"
echo "PASS"
