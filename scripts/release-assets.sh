#!/usr/bin/env bash
# release-assets.sh <tag>: gathers everything one Release needs into dist/.
# Expects the five built platforms in out/ (binaries, .sha256, .configure.txt).
. "$(dirname "$0")/lib.sh"
tag=$1
dist="$ROOT/dist"
rm -rf "$dist"; mkdir -p "$dist"

for p in linux-amd64 linux-arm64 darwin-amd64 darwin-arm64 windows-amd64; do
  exe=""; case $p in windows-*) exe=.exe ;; esac
  for f in "ffmpeg-$p$exe" "ffmpeg-$p$exe.sha256" "ffmpeg-$p.configure.txt"; do
    [ -f "$OUT/$f" ] || { echo "missing $OUT/$f" >&2; exit 1; }
    cp "$OUT/$f" "$dist/"
  done
  (cd "$dist" && sha256sum -c "ffmpeg-$p$exe.sha256")
done

# Corresponding source, exactly the tarballs the binaries were built from.
fetch "$FFMPEG_URL" "$FFMPEG_SHA256"
fetch "$OPUS_URL" "$OPUS_SHA256"
cp "$DL/${FFMPEG_URL##*/}" "$DL/${OPUS_URL##*/}" "$dist/"
tar -xJOf "$DL/${FFMPEG_URL##*/}" "ffmpeg-$FFMPEG_VERSION/COPYING.LGPLv2.1" > "$dist/COPYING.LGPLv2.1"
tar -xzOf "$DL/${OPUS_URL##*/}" "opus-$OPUS_VERSION/COPYING" > "$dist/LICENSE-opus.txt"
# The Linux binaries link musl statically (MIT); its notice must travel with them.
cp "$ROOT/licenses/musl-COPYRIGHT" "$dist/LICENSE-musl.txt"
# Build scripts and versions for this tag (no patches are applied to either source).
git -C "$ROOT" archive --format=tar.gz --prefix="ffmpeg-min-$tag/" -o "$dist/ffmpeg-min-$tag-build-scripts.tar.gz" HEAD

(cd "$dist" && sha256sum -- * > SHA256SUMS)
ls -l "$dist"
