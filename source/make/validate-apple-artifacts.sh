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

for artifact in libretrodlp.a libretrodlp-download.a; do
  "$legacy_lipo" "$build_root/macOS/$artifact" \
    -verify_arch ppc i386 x86_64 arm64
done

"$legacy_lipo" "$build_root/macOS/ppc-i386/retro-dlp" \
  -verify_arch ppc i386
"$legacy_lipo" "$build_root/macOS/x86_64-arm64/retro-dlp" \
  -verify_arch x86_64 arm64

for artifact in retro-dlp libretrodlp.a libretrodlp-download.a; do
  "$modern_lipo" "$build_root/iOS/$artifact" -verify_arch armv7 arm64
done

# Deployment load commands are properties of linked Mach-O images. Validate
# each executable slice independently; archives use the same compiled core
# objects, while legacy relocatable objects do not carry a minimum-OS command.
validate_minimum "$legacy_lipo" "$build_root/macOS/ppc-i386/retro-dlp" \
  ppc 10.4
validate_minimum "$legacy_lipo" "$build_root/macOS/ppc-i386/retro-dlp" \
  i386 10.4
validate_minimum "$legacy_lipo" \
  "$build_root/macOS/x86_64-arm64/retro-dlp" x86_64 10.9
validate_minimum "$legacy_lipo" \
  "$build_root/macOS/x86_64-arm64/retro-dlp" arm64 11.0
validate_minimum "$modern_lipo" "$build_root/iOS/retro-dlp" armv7 5.0
validate_minimum "$modern_lipo" "$build_root/iOS/retro-dlp" arm64 7.0

echo "PASS: Apple executables and libraries contain expected architectures"
echo "PASS: Apple executable slices declare expected deployment targets"
