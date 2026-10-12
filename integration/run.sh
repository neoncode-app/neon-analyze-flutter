#!/usr/bin/env bash
# Runs integration flows of the app in the current directory on one driver.
# neon-check calls it (step `integration`, command `neon-check integration`);
# it can also be run by hand from the app root:
#
#   neon-analyze-flutter/integration/run.sh --driver web-server -- integration_test/x_test.dart
#
# Drivers:
#   web-server  the real web app in Chrome through chromedriver (flutter drive
#               -d web-server; test_driver/integration_test.dart is the driver).
#               Needs chromedriver of Chrome's major version on PATH.
#   device      flutter test on a device or emulator (--device <id>, else the
#               only connected one).
#   none        nothing runs.
#
# A missing driver (no chromedriver, no device) skips with a notice and exits 0,
# or fails with NEON_INTEGRATION_REQUIRED=1 (set it in CI once the image has the
# driver). --defines <file> passes --dart-define-from-file (credentials of TEST
# accounts; the file is never committed). The output of every flow is also
# written to $NEON_INTEGRATION_LOG_DIR (build/neon-check/integration) as
# <flow>.log; a failing flow prints `integration: FAILED <file> <log>`. The
# exit code is 1 when any flow failed.
#
# Web notes (NCI0000015): with `-d chrome` flutter_tools opens a second,
# debugger-attached Chrome and the run never exits; `-d web-server` lets
# chromedriver's own Chrome open the app. CHROMEDRIVER_PORT (4444) and
# NEON_INTEGRATION_HEADLESS (1) can be overridden.
set -euo pipefail

driver=none
device=""
defines=""
while [ $# -gt 0 ]; do
  case "$1" in
    --driver) driver="$2"; shift 2 ;;
    --device) device="$2"; shift 2 ;;
    --defines) defines="$2"; shift 2 ;;
    --) shift; break ;;
    *) break ;;
  esac
done
files=("$@")

skip() {
  if [ "${NEON_INTEGRATION_REQUIRED:-0}" = "1" ]; then
    echo "integration: $1 and NEON_INTEGRATION_REQUIRED=1" >&2
    exit 1
  fi
  echo "integration: skipped, $1"
  exit 0
}

if [ "$driver" = "none" ]; then
  echo "integration: driver none, nothing runs"
  exit 0
fi
if [ ${#files[@]} -eq 0 ]; then
  echo "integration: no flows to run"
  exit 0
fi
define_args=()
if [ -n "$defines" ]; then define_args=(--dart-define-from-file="$defines"); fi
log_dir="${NEON_INTEGRATION_LOG_DIR:-build/neon-check/integration}"
mkdir -p "$log_dir"
log_of() { echo "$log_dir/$(basename "${1%.dart}").log"; }

rc=0
case "$driver" in
  web-server)
    command -v chromedriver >/dev/null 2>&1 || skip "chromedriver is not installed"
    [ -f test_driver/integration_test.dart ] || skip "test_driver/integration_test.dart is missing"
    port="${CHROMEDRIVER_PORT:-4444}"
    chromedriver --port="$port" >/dev/null 2>&1 &
    chromedriver_pid=$!
    trap 'kill "$chromedriver_pid" 2>/dev/null || true' EXIT
    sleep 1
    headless=()
    if [ "${NEON_INTEGRATION_HEADLESS:-1}" = "1" ]; then headless=(--headless); fi
    for file in "${files[@]}"; do
      echo "integration: $file"
      log="$(log_of "$file")"
      if ! flutter drive --driver=test_driver/integration_test.dart --target="$file" -d web-server \
          --driver-port="$port" "${headless[@]}" "${define_args[@]}" 2>&1 | tee "$log"; then
        echo "integration: FAILED $file $log" >&2
        rc=1
      fi
    done
    ;;
  device)
    if [ -z "$device" ]; then
      count="$(flutter devices --machine 2>/dev/null | grep -c '"id"' || true)"
      [ "${count:-0}" -ge 1 ] || skip "no device or emulator is connected"
    fi
    device_args=()
    if [ -n "$device" ]; then device_args=(-d "$device"); fi
    for file in "${files[@]}"; do
      echo "integration: $file"
      log="$(log_of "$file")"
      if ! flutter test "$file" "${device_args[@]}" "${define_args[@]}" 2>&1 | tee "$log"; then
        echo "integration: FAILED $file $log" >&2
        rc=1
      fi
    done
    ;;
  *)
    echo "integration: unknown driver '$driver' (web-server, device, none)" >&2
    exit 2
    ;;
esac
exit $rc
