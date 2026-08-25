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
nm -D "$binary" | grep -q ' U curl_easy_perform' || \
  fail "Linux binary is not linked to libcurl"

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
printf '%s\n' "$self_test_output" | grep -q '^PASS: video ID parsing' || \
  fail "--test did not pass video ID parsing"
printf '%s\n' "$self_test_output" | \
  grep -q '^PASS: deterministic player and HTTP classification fixtures$' || \
  fail "--test did not pass deterministic player fixtures"
printf '%s\n' "$self_test_output" | grep -q '^PASS: player API response' || \
  fail "--test did not pass the live player API test"
printf '%s\n' "$self_test_output" | grep -q '^PASS: media HEAD' || \
  fail "--test did not pass the media HEAD test"
printf '%s\n' "$self_test_output" | grep -q '^PASS: retro-dlp self-test$' || \
  fail "--test did not report success"

resolve_output=$($binary "https://youtu.be/YE7VzlLtp-4")
printf '%s\n' "$resolve_output" | grep -q '"itag":[[:space:]]*18' || \
  fail "video resolution did not return itag 18 JSON"
printf '%s\n' "$resolve_output" | grep -q 'googlevideo.com' || \
  fail "video resolution did not return a Google Video URL"
printf '%s\n' "$resolve_output" | \
  grep -Eq '"classification":[[:space:]]*"(ok|po_token_required)"' || \
  fail "video resolution did not classify the media probe"

python3 source/linux/test/yt_dlp_oracle.py "$binary" \
  inspiration/yt-dlp/yt_dlp/__main__.py

error_file=${TMPDIR:-/tmp}/retro-dlp-cli-test.$$
trap 'rm -f "$error_file"' EXIT HUP INT TERM
if $binary --not-an-option 2>"$error_file"; then
  fail "unsupported arguments returned success"
fi
grep -q '^retro-dlp: unsupported arguments$' "$error_file" || \
  fail "unsupported arguments did not report an error"

echo "PASS: Linux CLI"
