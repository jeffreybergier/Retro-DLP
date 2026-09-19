#!/bin/sh

set -eu

legacy_lipo=${1:?usage: validate-apple-artifacts.sh LEGACY_LIPO MODERN_LIPO OTOOL BUILD_DIR}
modern_lipo=${2:?usage: validate-apple-artifacts.sh LEGACY_LIPO MODERN_LIPO OTOOL BUILD_DIR}
otool=${3:?usage: validate-apple-artifacts.sh LEGACY_LIPO MODERN_LIPO OTOOL BUILD_DIR}
build_root=${4:?usage: validate-apple-artifacts.sh LEGACY_LIPO MODERN_LIPO OTOOL BUILD_DIR}
temporary=$(mktemp -d "${TMPDIR:-/tmp}/retro-dlp-apple-validation.XXXXXX")

cleanup() {
  case "$temporary" in
    "${TMPDIR:-/tmp}"/retro-dlp-apple-validation.*) rm -rf -- "$temporary" ;;
  esac
}
trap cleanup EXIT HUP INT TERM

validate_minimum() {
  validation_lipo=$1
  validation_artifact=$2
  validation_architecture=$3
  validation_minimum=$4
  validation_thin=$temporary/$(basename "$validation_artifact").$validation_architecture
  "$validation_lipo" "$validation_artifact" -thin \
    "$validation_architecture" -output "$validation_thin"
  "$otool" -l "$validation_thin" | \
    grep -Eq "(version|minos)[[:space:]]+$validation_minimum([[:space:]]|$)"
}

# Require exactly the supported slices; -verify_arch alone permits extras.
validate_architectures() {
  validation_lipo=$1
  validation_artifact=$2
  validation_expected=$3
  validation_actual=$("$validation_lipo" -archs "$validation_artifact" | \
    tr ' ' '\n' | sed '/^$/d' | LC_ALL=C sort | tr '\n' ' ')
  if [ "$validation_actual" != "$validation_expected" ]; then
    echo "Unexpected architectures in $validation_artifact: $validation_actual" >&2
    exit 1
  fi
}

for artifact in ppc-i386/retro-dlp libretrodlp.a libretrodlp-download.a; do
  # The legacy lipo can assemble/thin PowerPC slices but lacks -archs.
  validate_architectures "$modern_lipo" "$build_root/macOS/$artifact" "i386 ppc "
done

for artifact in retro-dlp libretrodlp.a libretrodlp-download.a; do
  validate_architectures "$modern_lipo" "$build_root/iOS/$artifact" "arm64 armv7 "
done

# Deployment load commands are properties of linked Mach-O images. Validate
# each executable slice independently; archives use the same compiled core
# objects, while legacy relocatable objects do not carry a minimum-OS command.
validate_minimum "$legacy_lipo" "$build_root/macOS/ppc-i386/retro-dlp" \
  ppc 10.4
validate_minimum "$legacy_lipo" "$build_root/macOS/ppc-i386/retro-dlp" \
  i386 10.4
validate_minimum "$modern_lipo" "$build_root/iOS/retro-dlp" armv7 5.0
validate_minimum "$modern_lipo" "$build_root/iOS/retro-dlp" arm64 7.0

echo "PASS: Apple executables and libraries contain expected architectures"
echo "PASS: Apple executable slices declare expected deployment targets"
