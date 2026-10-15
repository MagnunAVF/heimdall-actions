#!/usr/bin/env bash
# Tests for scripts/require-collaborator.sh. A fake `gh` on PATH answers the collaborator API,
# so this never talks to GitHub. Run: bash scripts/require-collaborator_test.sh
set -u

here=$(cd "$(dirname "$0")" && pwd)
script="$here/require-collaborator.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"
# Collaborators: alice. Anyone else gets a 404, like the real API.
cat >"$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_GH_LOG"
[ -n "${FAKE_GH_FAIL:-}" ] && { echo "gh: HTTP 401: Bad credentials" >&2; exit 1; }
[ "$1" = api ] && [ "$2" = "repos/{owner}/{repo}/collaborators/alice" ] && exit 0
echo "gh: Not Found (HTTP 404)" >&2; exit 1
EOF
chmod +x "$tmp/bin/gh"
export FAKE_GH_LOG="$tmp/gh.log"
: >"$FAKE_GH_LOG"

pass=0 fail=0
# check <name> <want-exit> <want-stderr-substring> -- <args...>
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

check "collaborator"             0 "" -- alice
check "not a collaborator"       1 "mallory is not a collaborator" -- mallory
check "bot account"              1 "claude[bot] is not a collaborator" -- "claude[bot]"
FAKE_GH_FAIL=1 \
  check "gh failure fails closed" 1 "Bad credentials" -- alice
check "no args"                  2 "usage:" --
check "empty user"               2 "usage:" -- ""
check "two args"                 2 "usage:" -- alice bob
check "user with a slash"        2 "usage:" -- "alice/../../x"

# A rejected login must never reach the API path.
if grep -q '\.\.' "$FAKE_GH_LOG"; then
  fail=$((fail + 1)); echo "FAIL invalid login was sent to gh"; else pass=$((pass + 1)); fi

echo "require-collaborator: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
