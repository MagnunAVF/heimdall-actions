#!/usr/bin/env bash
# Tests for scripts/close-eng-issue.sh. A fake `gh` on PATH serves a canned issue list and logs
# every other call, so this never talks to GitHub. Run: bash scripts/close-eng-issue_test.sh
set -u

here=$(cd "$(dirname "$0")" && pwd)
script="$here/close-eng-issue.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_GH_FAIL:-}" ] && { echo "gh: HTTP 401: Bad credentials" >&2; exit 1; }
if [ "$1 $2" = "issue list" ]; then cat "$FAKE_GH_JSON"; else printf '%s\n' "$*" >>"$FAKE_GH_LOG"; fi
EOF
chmod +x "$tmp/bin/gh"

# Titles carry the plan-order id; GitHub numbers differ.
cat >"$tmp/issues.json" <<'EOF'
[
  {"number": 1, "title": "ENG-1: [0.1a] GitHub automation"},
  {"number": 2, "title": "ENG-3: [0.1c] MCP servers"},
  {"number": 5, "title": "ci: add Claude Code GitHub Workflow"}
]
EOF
export FAKE_GH_JSON="$tmp/issues.json" FAKE_GH_LOG="$tmp/gh.log"
url=https://github.com/o/r/pull/9

pass=0 fail=0
# check <name> <want-exit> <want-gh-calls> <want-stderr-substring> -- <args...>
# want-gh-calls is the exact log of gh calls other than "issue list" ("" for none).
check() {
  local name=$1 want_code=$2 want_calls=$3 want_err=$4
  shift 5
  local err code calls
  : >"$FAKE_GH_LOG"
  PATH="$tmp/bin:$PATH" bash "$script" "$@" >/dev/null 2>"$tmp/stderr"
  code=$?
  err=$(cat "$tmp/stderr")
  calls=$(cat "$FAKE_GH_LOG")
  if [ "$code" = "$want_code" ] && [ "$calls" = "$want_calls" ] &&
    { [ -z "$want_err" ] || [[ "$err" == *"$want_err"* ]]; }; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n  exit:   got %s want %s\n  gh:     got %q want %q\n  stderr: got %q want *%s*\n' \
      "$name" "$code" "$want_code" "$calls" "$want_calls" "$err" "$want_err"
  fi
}

check "ENG id in branch"        0 "issue close 2 --comment ENG-3 done in $url (merged into dev)." "" -- chore/ENG-3-mcp "$url"
check "ENG id equal to number"  0 "issue close 1 --comment ENG-1 done in $url (merged into dev)." "" -- chore/ENG-1-ci "$url"
check "claude/issue-n branch"   0 "issue close 2 --comment ENG-3 done in $url (merged into dev)." "" -- claude/issue-2-x "$url"
check "plan branch"             0 "" "" -- docs/plan-M0 "$url"
check "unknown ENG id"          1 "" "no issue titled ENG-99" -- feat/ENG-99-x "$url"
check "claude/issue without ENG" 1 "" "issue 5 not found or has no ENG-<n> title" -- claude/issue-5 "$url"
FAKE_GH_FAIL=1 \
  check "gh failure"            1 "" "Bad credentials" -- chore/ENG-3-mcp "$url"
check "no args"                 2 "" "usage:" --
check "one arg"                 2 "" "usage:" -- chore/ENG-3-mcp

echo "close-eng-issue: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
