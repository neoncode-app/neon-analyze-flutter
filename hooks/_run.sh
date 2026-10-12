#!/usr/bin/env bash
# Shared body of the git hooks (core.hooksPath = neon-analyze-flutter/hooks,
# set by `neon-check install`). An app's own hook of the same name
# (.githooks/<name> or tool/git-hooks/<name>) runs first, so moving an app
# onto the shared hooks drops nothing. Then the trigger of the same name runs,
# if the hook has one.
#
#   _run.sh <hook name> [<trigger>] -- <git hook arguments>
set -euo pipefail

name="$1"
shift
trigger=""
if [ "${1:-}" != "--" ]; then
  trigger="$1"
  shift
fi
[ "${1:-}" = "--" ] && shift

root="$(git rev-parse --show-toplevel)"
for dir in .githooks tool/git-hooks; do
  if [ -x "$root/$dir/$name" ]; then
    "$root/$dir/$name" "$@"
  fi
done

if [ -n "$trigger" ] && [ -f "$root/neon_check.yaml" ]; then
  exec "$root/neon-analyze-flutter/bin/neon-check" --trigger "$trigger" --max-failures 30
fi
