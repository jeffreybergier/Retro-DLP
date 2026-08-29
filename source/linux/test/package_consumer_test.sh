#!/bin/sh

set -eu

source_root=${1:?usage: package_consumer_test.sh SOURCE BUILD CC CFLAGS LDFLAGS LDLIBS}
build_root=${2:?usage: package_consumer_test.sh SOURCE BUILD CC CFLAGS LDFLAGS LDLIBS}
compiler=${3:?usage: package_consumer_test.sh SOURCE BUILD CC CFLAGS LDFLAGS LDLIBS}
compile_flags=${4-}
link_flags=${5-}
link_libraries=${6-}
temporary=$(mktemp -d "${TMPDIR:-/tmp}/retro-dlp-package-test.XXXXXX")

cleanup() {
  case "$temporary" in
    "${TMPDIR:-/tmp}"/retro-dlp-package-test.*) rm -rf -- "$temporary" ;;
  esac
}
trap cleanup EXIT HUP INT TERM

"${MAKE:-make}" --no-print-directory -C "$source_root" install \
  BUILD_DIR="$build_root" DESTDIR="$temporary/stage" PREFIX=/usr >/dev/null

test -f "$temporary/stage/usr/include/retrodlp/retrodlp.h"
test -f "$temporary/stage/usr/include/retrodlp/download.h"
test -f "$temporary/stage/usr/include/retrodlp/version.h"
test -f "$temporary/stage/usr/lib/libretrodlp.a"
test -f "$temporary/stage/usr/lib/libretrodlp-download.a"

cp "$source_root/source/linux/test/public_header_c99.c" "$temporary/"
cp "$source_root/source/linux/test/public_consumer.c" "$temporary/"
cd "$temporary"

# Deliberate field splitting preserves conventional multi-word compiler flags.
# shellcheck disable=SC2086
$compiler $compile_flags -std=c99 -pedantic-errors -Wall -Wextra -Werror \
  -I"$temporary/stage/usr/include" -c public_header_c99.c \
  -o public_header_c99.o
# shellcheck disable=SC2086
$compiler $compile_flags -std=c99 -pedantic-errors -Wall -Wextra -Werror \
  -I"$temporary/stage/usr/include" -c public_consumer.c \
  -o public_consumer.o
# shellcheck disable=SC2086
$compiler $link_flags public_consumer.o \
  "$temporary/stage/usr/lib/libretrodlp.a" \
  -lcurl -lcrypto -lm -ldl -lpthread $link_libraries \
  -o public_consumer

./public_consumer
echo "PASS: installed public headers compile as C99"
echo "PASS: out-of-tree installed-library consumer"
