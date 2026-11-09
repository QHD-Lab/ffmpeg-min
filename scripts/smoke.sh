#!/usr/bin/env bash
# smoke.sh <ffmpeg binary>: checks the license and components, then runs the
# iCrew audio path end to end over RTSP on 127.0.0.1, using only this binary:
#   publish h264-aac.mp4 -> [listen, video copy, AAC -> libopus, publish] -> [listen, check H264 + Opus]
set -euo pipefail
FF=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
TEST=$(cd "$(dirname "$0")/../test" && pwd)
cd "$(dirname "$0")/../test/fixtures"
TMP=$(mktemp -d)
trap 'kill $(jobs -p) 2>/dev/null || true' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ff() { "$FF" -hide_banner -nostdin "$@"; }

version=$(ff -version | sed -n 1p); echo "$version"
case $version in *-icrew.*) ;; *) fail "not the patched build (no -icrew.N in the version)" ;; esac
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

# patches/0001-rtsp-auth_file.patch: the option exists on both sides and bad input fails.
for side in demuxer muxer; do
  ff -h $side=rtsp > "$TMP/h-$side" 2>&1
  grep -q -- "-auth_file" "$TMP/h-$side" || fail "rtsp $side has no auth_file option"
done
# iCrew passes the credential on an inherited pipe, fd 3; on Windows Git Bash cannot hand
# fd 3 to a native program, so test/pipe3.mjs does it with Node's spawn, as iCrew does.
SECRET=icrew-ffmpeg:smoke-$$-secret
ff3() {
  case $(uname -s) in
    MINGW*|MSYS*|CYGWIN*) SMOKE_SECRET=$SECRET node "$TEST/pipe3.mjs" "$FF" -hide_banner -nostdin "$@" ;;
    *) ff "$@" 3< <(echo "$SECRET") ;;
  esac
}
b64() { printf %s "$1" | base64 | tr -d '\r\n'; }
# cred <bytes> <tag>: a user:password exactly <bytes> long.
cred() { local c=icrew-ffmpeg:$2-$$-; printf '%s%s' "$c" "$(printf "%0$(($1 - ${#c}))d" 0 | tr 0 y)"; }
LONG=$(cred 127 long)
NOWHERE=rtsp://127.0.0.1:1/x
printf '\n' > "$TMP/newline"
: > "$TMP/empty"
printf '%s' "$(cred 128 over)" > "$TMP/128"
printf '%s\n%s' "$LONG" "$(cred 32 tail)" > "$TMP/tail"
printf 'u:p\nx:y\n' > "$TMP/twolines"
printf '%s\n' "$LONG" > "$TMP/127"
# expect_auth_error <message> <ffmpeg args...>: must exit non-zero because of auth_file.
expect_auth_error() {
  local want=$1; shift
  if ff "$@" > "$TMP/auth-err.log" 2>&1; then fail "auth_file case succeeded: $*"; fi
  grep -q "$want" "$TMP/auth-err.log" || { cat "$TMP/auth-err.log"; fail "auth_file case gave the wrong error: $*"; }
}
expect_auth_error "Could not open auth_file" -auth_file "$TMP/missing" -i $NOWHERE -f null -
expect_auth_error "Could not open auth_file" -auth_file http://127.0.0.1:1/auth -i $NOWHERE -f null -
for f in empty newline 128 tail twolines; do
  expect_auth_error "auth_file must hold" -i ac3.mp4 -c copy -auth_file "$TMP/$f" -f rtsp $NOWHERE
done
echo "ok   auth_file: on rtsp demuxer and muxer; missing, non-file/pipe, empty, 128-byte, 127+LF+tail, two-line sources fail"

# Against a server that answers 401 Basic, at -loglevel trace: the credential must reach the
# server intact (127 bytes from a file, SECRET from pipe:3) and appear in no log, as text or Base64.
node "$TEST/rtsp401.mjs" 18556 "$TMP/auth-record.txt" 2 & srv=$!
sleep 2
if ff3 -loglevel trace -rtsp_transport tcp -auth_file pipe:3 -i rtsp://127.0.0.1:18556/pgm-in \
  -f null - > "$TMP/trace-demux.log" 2>&1; then fail "401 server: demuxer succeeded"; fi
if ff -loglevel trace -i h264-aac.mp4 -c copy -rtsp_transport tcp -auth_file "$TMP/127" \
  -f rtsp rtsp://127.0.0.1:18556/pgm-out > "$TMP/trace-mux.log" 2>&1; then fail "401 server: muxer succeeded"; fi
wait $srv || true
printf 'Basic %s\nBasic %s\n' "$(b64 "$SECRET")" "$(b64 "$LONG")" > "$TMP/auth-want.txt"
cmp -s "$TMP/auth-record.txt" "$TMP/auth-want.txt" \
  || { cat "$TMP/trace-demux.log" "$TMP/trace-mux.log"; fail "401 server did not get the credentials intact"; }
for t in demux mux; do
  grep -q "Authorization: <redacted>" "$TMP/trace-$t.log" || { cat "$TMP/trace-$t.log"; fail "no redacted Authorization in trace-$t"; }
done
for v in "$SECRET" "$(b64 "$SECRET")" "$LONG" "$(b64 "$LONG")"; do
  ! grep -lF -- "$v" "$TMP"/*.log || fail "a credential leaked into a log"
done
echo "ok   auth_file: 401 Basic retry sends the credential intact (pipe:3, 127-byte file); trace logs show it redacted"

IN=rtsp://127.0.0.1:18554/pgm-in OUT=rtsp://127.0.0.1:18555/pgm-out
# Both publishers read SECRET from pipe:3. Listen mode does not check it; this proves it is
# read without breaking the stream.
ff -rtsp_flags listen -listen_timeout 30 -i $OUT -c copy -f null - > "$TMP/view.log" 2>&1 & view=$!
sleep 2
ff3 -rtsp_flags listen -listen_timeout 30 -i $IN -map 0:v:0 -map 0:a:0 -c:v copy \
  -c:a libopus -ar 48000 -ac 2 -b:a 96k -application lowdelay -frame_duration 20 \
  -rtsp_transport tcp -auth_file pipe:3 -f rtsp $OUT > "$TMP/bridge.log" 2>&1 & bridge=$!
sleep 2
ff3 -re -i h264-aac.mp4 -c copy -rtsp_transport tcp -auth_file pipe:3 -f rtsp $IN > "$TMP/pub.log" 2>&1 \
  || { cat "$TMP/pub.log"; fail "publish"; }
wait $bridge || { cat "$TMP/bridge.log"; fail "bridge exited with an error"; }
wait $view || { cat "$TMP/view.log"; fail "viewer exited with an error"; }
grep -q "Video: h264" "$TMP/view.log" && grep -q "Audio: opus, 48000 Hz, stereo" "$TMP/view.log" \
  || { cat "$TMP/view.log"; fail "pgm-out is not H264 + Opus"; }
frames=$(grep -o "frame= *[0-9]*" "$TMP/view.log" | tail -1 | tr -dc 0-9)
[ "${frames:-0}" -ge 55 ] || { cat "$TMP/view.log"; fail "pgm-out got only ${frames:-0} of 60 video frames"; }
! grep -lF -e "$SECRET" -e "$(b64 "$SECRET")" "$TMP"/*.log || fail "the auth_file credential leaked into a log"
echo "ok   RTSP: H264+AAC in -> H264 (copy) + Opus 48 kHz stereo out, $frames video frames; credential via pipe:3, not logged"
echo "PASS"
