#!/usr/bin/env bash
# Tests for scripts/pr-check.sh. A fake `gh` on PATH serves a canned issue list (used by
# eng-issue.sh), so this never talks to GitHub. Run: bash scripts/pr-check_test.sh
set -u

here=$(cd "$(dirname "$0")" && pwd)
script="$here/pr-check.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_GH_FAIL:-}" ] && { echo "gh: HTTP 401: Bad credentials" >&2; exit 1; }
cat "$FAKE_GH_JSON"
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
export FAKE_GH_JSON="$tmp/issues.json"

pass=0 fail=0
# check <name> <want-exit> <want-stderr-substring> -- <base> <head> <title>
check() {
  local name=$1 want_code=$2 want_err=$3
  shift 4
  local err code
  PATH="$tmp/bin:$PATH" bash "$script" "$@" >/dev/null 2>"$tmp/stderr"
  code=$?
  err=$(cat "$tmp/stderr")
  if [ "$code" = "$want_code" ] &&
    { [ -z "$want_err" ] && [ -z "$err" ] || [ -n "$want_err" ] && [[ "$err" == *"$want_err"* ]]; }; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n  exit:   got %s want %s\n  stderr: got %q want *%s*\n' \
      "$name" "$code" "$want_code" "$err" "$want_err"
  fi
}

check "conforming PR"                 0 "" -- dev chore/ENG-1-x "chore(ci): x (ENG-1)"
check "title without ENG id"          1 "must end with (ENG-1)" -- dev chore/ENG-1-x "chore(ci): x"
check "title names another ENG id"    1 "must end with (ENG-1)" -- dev chore/ENG-1-x "chore(ci): x (ENG-3)"
check "title with #n"                 1 "not #<n>" -- dev chore/ENG-1-x "chore(ci): fix #4 (ENG-1)"
check "plan branch is exempt"         0 "" -- dev docs/plan-M0 "docs(plan): M0 plan"
check "release branch is exempt"      0 "" -- dev release/v0.1.0 "release notes"
check "back-merge from main"          0 "" -- dev main "Back-merge main"
check "Claude app setup PR"           0 "" -- dev add-claude-github-actions-123 "Add Claude"
check "plan branch needs a number"    1 "Branch must contain ENG-<n>" -- dev docs/plan-Mx "x"
check "unknown ENG id"                1 'no issue title starts with "ENG-99:"' -- dev feat/ENG-99-x "feat: x (ENG-99)"
check "branch without ENG id"         1 "Branch must contain ENG-<n>" -- dev feature-x "feat: x"
check "claude/issue-n maps to ENG id" 0 "" -- dev claude/issue-2 "feat: x (ENG-3)"
check "claude/issue-n wrong title"    1 "must end with (ENG-3)" -- dev claude/issue-2 "feat: x (ENG-2)"
check "claude/issue-n without ENG"    1 "Issue 5 has no ENG-<n> title" -- dev claude/issue-5 "ci: x"
check "release into main"             0 "" -- main dev "release: v0.1.0"
check "hotfix into main"              0 "" -- main hotfix/login "fix: login"
check "feature into main"             1 "must come from dev or hotfix/*" -- main feat/ENG-1-x "feat: x (ENG-1)"
check "other base"                    1 "must target dev" -- release feat/ENG-1-x "feat: x (ENG-1)"
check "no args"                       2 "usage:" --
check "two args"                      2 "usage:" -- dev chore/ENG-1-x
FAKE_GH_FAIL=1 \
  check "gh failure fails the check"  1 "Bad credentials" -- dev chore/ENG-1-x "chore(ci): x (ENG-1)"

echo "pr-check: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
