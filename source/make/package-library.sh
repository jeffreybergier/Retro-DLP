#!/bin/sh

set -eu

platform=${1:?usage: package-library.sh PLATFORM BUILD_DIR}
build_root=${2:?usage: package-library.sh PLATFORM BUILD_DIR}
platform_root=$build_root/$platform
archive=$platform_root/retro-dlp-library.zip
stage=$build_root/intermediates/packages/$platform

case "$stage" in
  */intermediates/packages/linux|*/intermediates/packages/macOS|*/intermediates/packages/iOS)
    rm -rf -- "$stage"
    ;;
  *)
    echo "Refusing unsafe package staging path: $stage" >&2
    exit 1
    ;;
esac

mkdir -p "$stage/include/retrodlp" "$stage/lib" "$stage/examples"
cp include/retrodlp/retrodlp.h include/retrodlp/download.h \
  include/retrodlp/version.h "$stage/include/retrodlp/"
cp "$platform_root/libretrodlp.a" \
  "$platform_root/libretrodlp-download.a" "$stage/lib/"
cp docs/library-api.md "$stage/README.md"
cp examples/*.c examples/README.md "$stage/examples/"
cp LICENSE "$stage/LICENSE"

# ZIP stores DOS timestamps. Normalize the staged copies so rebuilding the same
# inputs produces byte-identical packages without changing source artifacts.
find "$stage" -exec touch -t 198001010000 {} +

rm -f -- "$archive"
(
  cd "$stage"
  zip -9 -X -q -r retro-dlp-library.zip.tmp LICENSE README.md examples \
    include lib
)
mv "$stage/retro-dlp-library.zip.tmp" "$archive"
echo "  > $archive ($platform static libraries)"
