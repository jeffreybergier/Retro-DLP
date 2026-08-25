#!/bin/sh

set -eu

binary=${1:?usage: cli_test.sh /path/to/retro-dlp}

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

nm "$binary" | grep -q ' cJSON_Parse$' || \
  fail "Linux binary does not contain cJSON"
nm "$binary" | grep -q ' JS_NewRuntime$' || \
  fail "Linux binary does not contain QuickJS"

help_output=$($binary --help)
printf '%s\n' "$help_output" | grep -q '^Usage: retro-dlp' || \
  fail "--help did not print usage"

version_output=$($binary --version)
[ "$version_output" = "retro-dlp 0.1.0 (Linux)" ] || \
  fail "unexpected --version output: $version_output"

self_test_output=$($binary --test)
printf '%s\n' "$self_test_output" | grep -q '^PASS: cJSON$' || \
  fail "--test did not pass cJSON"
printf '%s\n' "$self_test_output" | grep -q '^PASS: QuickJS$' || \
  fail "--test did not pass QuickJS"
printf '%s\n' "$self_test_output" | grep -q '^PASS: retro-dlp self-test$' || \
  fail "--test did not report success"

error_file=${TMPDIR:-/tmp}/retro-dlp-cli-test.$$
trap 'rm -f "$error_file"' EXIT HUP INT TERM
if $binary --not-an-option 2>"$error_file"; then
  fail "unsupported arguments returned success"
fi
grep -q '^retro-dlp: unsupported arguments$' "$error_file" || \
  fail "unsupported arguments did not report an error"

echo "PASS: Linux CLI"
