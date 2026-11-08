# Shared build steps. Sourced by scripts/build-<platform>.sh; not run directly.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../versions.env
. "$ROOT/versions.env"
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu)}
DL="$ROOT/build/dl"
OUT="$ROOT/out"

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }

# fetch <url> <sha256>: download once into build/dl and verify.
fetch() {
  local file="$DL/${1##*/}"
  mkdir -p "$DL"
  if [ ! -f "$file" ]; then
    curl -fsSL --retry 3 -o "$file.part" "$1"
    mv "$file.part" "$file"
  fi
  local got; got=$(sha256 "$file")
  if [ "$got" != "$2" ]; then echo "sha256 mismatch for $file: $got" >&2; rm -f "$file"; exit 1; fi
}

# The only components iCrew needs: RTSP in and out, video stream copy,
# AAC / AC-3 / MPEG audio decoding, Opus encoding through libopus.
FFMPEG_COMPONENTS=(
  --disable-everything --disable-autodetect --disable-iconv
  --disable-doc --disable-ffplay --disable-ffprobe --disable-avdevice --disable-swscale
  --disable-debug --enable-small
  --enable-network
  --enable-protocol=file,pipe,tcp,udp,rtp
  --enable-demuxer=rtsp,sdp,rtp,mov
  --enable-muxer=rtsp,rtp,null
  --enable-parser=h264,hevc,aac,aac_latm,ac3,mpegaudio,opus
  --enable-bsf=h264_mp4toannexb,hevc_mp4toannexb,extract_extradata,aac_adtstoasc
  --enable-decoder=aac,aac_latm,ac3,eac3,mp1,mp1float,mp2,mp2float,mp3,mp3float
  --enable-libopus --enable-encoder=libopus
  --enable-filter=abuffer,abuffersink,aresample,aformat,anull,atrim,buffer,buffersink,null,format,trim
)

# build <platform> <opus configure args...> -- <ffmpeg configure args...>
# Writes out/ffmpeg-<platform>[.exe], its .sha256 and .configure.txt.
build() {
  local platform=$1; shift
  local opus_args=() ff_args=()
  while [ $# -gt 0 ] && [ "$1" != -- ]; do opus_args+=("$1"); shift; done
  [ $# -gt 0 ] && shift
  ff_args=("$@")

  local work="$ROOT/build/$platform" prefix="$ROOT/build/$platform/prefix"
  rm -rf "$work"; mkdir -p "$work/src" "$OUT"

  fetch "$OPUS_URL" "$OPUS_SHA256"
  fetch "$FFMPEG_URL" "$FFMPEG_SHA256"
  tar -xzf "$DL/${OPUS_URL##*/}" -C "$work/src"
  tar -xJf "$DL/${FFMPEG_URL##*/}" -C "$work/src"

  echo "== libopus $OPUS_VERSION ($platform)"
  (cd "$work/src/opus-$OPUS_VERSION" &&
    ./configure --prefix="$prefix" --enable-static --disable-shared \
      --disable-doc --disable-extra-programs "${opus_args[@]}" &&
    make -j"$JOBS" && make install)

  echo "== FFmpeg $FFMPEG_VERSION ($platform)"
  # PKG_CONFIG_LIBDIR keeps configure from finding anything but our libopus.
  (cd "$work/src/ffmpeg-$FFMPEG_VERSION" &&
    PKG_CONFIG_LIBDIR="$prefix/lib/pkgconfig" ./configure \
      --pkg-config=pkg-config --pkg-config-flags=--static \
      "${FFMPEG_COMPONENTS[@]}" "${ff_args[@]}" &&
    make -j"$JOBS")

  local exe="" bin
  case $platform in windows-*) exe=.exe ;; esac
  bin="ffmpeg-$platform$exe"
  cp "$work/src/ffmpeg-$FFMPEG_VERSION/ffmpeg$exe" "$OUT/$bin"
  (cd "$OUT" && echo "$(sha256 "$bin")  $bin" > "$bin.sha256")
  sed -n 's/^FFMPEG_CONFIGURATION=//p' "$work/src/ffmpeg-$FFMPEG_VERSION/ffbuild/config.mak" > "$OUT/ffmpeg-$platform.configure.txt"
  echo "== built $OUT/$bin ($(wc -c < "$OUT/$bin" | tr -d ' ') bytes)"
}

# require_host <uname -s> <uname -m...>: these builds are native, not cross.
require_host() {
  local os=$1; shift
  if [ "$(uname -s)" = "$os" ]; then
    for m in "$@"; do [ "$(uname -m)" = "$m" ] && return 0; done
  fi
  echo "this script must run on $os $* (got $(uname -s) $(uname -m))" >&2; exit 1
}
