#!/usr/bin/env bash
cd "$CLAUDE_PROJECT_DIR" || exit 0
input=$(cat)
[ "$(echo "$input" | jq -r '.stop_hook_active')" = "true" ] && exit 0

git diff --quiet && git diff --cached --quiet && exit 0

# Until M1 adds the Makefile there is nothing to run.
grep -q '^check:' Makefile 2>/dev/null || exit 0

if ! out=$(make -s check 2>&1); then
  echo "make check is failing. Fix it before finishing:" >&2
  echo "$out" | tail -40 >&2
  exit 2
fi
