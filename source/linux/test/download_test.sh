#!/bin/sh

set -eu

binary=${1:?usage: download_test.sh /path/to/download-consumer}
fixture_dir=$(mktemp -d "${TMPDIR:-/tmp}/retro-dlp-download-server.XXXXXX")
certificate=$fixture_dir/certificate.pem
key=$fixture_dir/key.pem
port_file=$fixture_dir/port
server_pid=

cleanup() {
  if [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  case "$fixture_dir" in
    "${TMPDIR:-/tmp}"/retro-dlp-download-server.*) rm -rf -- "$fixture_dir" ;;
  esac
}
trap cleanup EXIT HUP INT TERM

openssl req -x509 -newkey rsa:2048 -nodes -days 1 \
  -subj /CN=localhost -addext subjectAltName=DNS:localhost \
  -keyout "$key" -out "$certificate" >/dev/null 2>&1
python3 source/linux/test/download_server.py \
  "$certificate" "$key" "$port_file" &
server_pid=$!

attempt=0
while [ ! -s "$port_file" ]; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 100 ]; then
    echo "FAIL: HTTPS download fixture server did not start" >&2
    exit 1
  fi
  sleep 0.05
done

RETRO_DLP_TEST_DOWNLOAD_URL="https://localhost:$(cat "$port_file")"
RETRO_DLP_TEST_DOWNLOAD_CA=$certificate
export RETRO_DLP_TEST_DOWNLOAD_URL RETRO_DLP_TEST_DOWNLOAD_CA
output=$("$binary" 2>&1)
expected='PASS: download failures, cleanup, cancellation, and mux retention'
if [ "$output" != "$expected" ]; then
  printf '%s\n' "$output" >&2
  echo "FAIL: optional download library wrote unexpected process output" >&2
  exit 1
fi
printf '%s\n' "$output"
