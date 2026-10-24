#!/usr/bin/env bash
# Tests for the Makefile. Each case copies it into a throwaway git repo and replaces every tool
# (go, golangci-lint, sqlc, npm, docker compose) with a stub that logs its arguments, so this
# never builds Go code, installs packages or starts containers. Run: bash scripts/makefile_test.sh
set -u

here=$(cd "$(dirname "$0")" && pwd)
makefile="$here/../Makefile"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

bin="$tmp/bin" logs="$tmp/logs"
mkdir -p "$bin" "$logs"
for tool in go golangci-lint sqlc npm compose; do
  cat >"$bin/$tool" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$logs/$tool.log"
if [ "$tool" = sqlc ] && [ -n "\${FAKE_DIRTY:-}" ]; then
  mkdir -p internal/store/db && echo "package db" >internal/store/db/new.go
fi
[ "\${FAKE_FAIL:-}" = "$tool" ] && exit 1
exit 0
EOF
  chmod +x "$bin/$tool"
done

# fresh: a new project with the Makefile, one passing script test and a passing hooks test.
proj="$tmp/proj"
fresh() {
  rm -rf "$proj" "$logs"/*
  mkdir -p "$proj/scripts" "$proj/.claude/hooks"
  cp "$makefile" "$proj/Makefile"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$proj/scripts/ok_test.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$proj/.claude/hooks/hooks_test.sh"
  git -C "$proj" init -q
  git -C "$proj" add . && git -C "$proj" -c user.name=t -c user.email=t@t commit -qm init
}
log() { cat "$logs/$1.log" 2>/dev/null; }

pass=0 fail=0
# check <name> <want-exit: 0|fail> <want-output-substring> <tool> <want-tool-log> -- <make args...>
# want-tool-log is the exact log of calls to <tool> ("" for none; tool "-" skips the check).
check() {
  local name=$1 want_code=$2 want_out=$3 tool=$4 want_log=$5
  shift 6
  local out code got_log=""
  out=$(make -C "$proj" -s "$@" GO="$bin/go" GOLANGCI_LINT="$bin/golangci-lint" \
    SQLC="$bin/sqlc" NPM="$bin/npm" COMPOSE="$bin/compose" 2>&1)
  code=$?
  [ "$tool" != - ] && got_log=$(log "$tool")
  if { { [ "$want_code" = 0 ] && [ "$code" = 0 ]; } || { [ "$want_code" = fail ] && [ "$code" != 0 ]; }; } &&
    { [ "$tool" = - ] || [ "$got_log" = "$want_log" ]; } &&
    { [ -z "$want_out" ] || [[ "$out" == *"$want_out"* ]]; }; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n  exit:   got %s want %s\n  %s log: got %q want %q\n  output: %s\n' \
      "$name" "$code" "$want_code" "$tool" "$got_log" "$want_log" "$out"
  fi
}

# Missing inputs: skip with a message, call nothing.
fresh
check "generate without sqlc.yaml"       0 "skip:" sqlc    "" -- generate
check "generate-check without sqlc.yaml" 0 "skip:" sqlc    "" -- generate-check
check "web-check without web/"           0 "skip:" npm     "" -- web-check
check "up without compose file"          0 "skip:" compose "" -- up
check "down without compose file"        0 "skip:" compose "" -- down

# Go targets.
fresh
check "lint"             0 "" golangci-lint "run ./..." -- lint
check "test"             0 "" go "test -race ./..." -- test
fresh
check "test-integration" 0 "" go "test -race -tags integration -count=1 ./..." -- test-integration

# sqlc.
fresh
touch "$proj/sqlc.yaml"
check "generate"                  0 "" sqlc "generate" -- generate
check "generate-check, clean"     0 "" sqlc "generate
generate" -- generate-check
fresh
touch "$proj/sqlc.yaml"
FAKE_DIRTY=1 \
  check "generate-check, dirty"   fail "internal/store/db" sqlc "generate" -- generate-check

# Web.
fresh
mkdir -p "$proj/web" && echo '{}' >"$proj/web/package.json"
check "web-check"         0 "" npm "run lint
run typecheck
run test" -- web-check
fresh
mkdir -p "$proj/web" && echo '{}' >"$proj/web/package.json"
FAKE_FAIL=npm \
  check "web-check, lint fails" fail "" npm "run lint" -- web-check

# Compose.
fresh
mkdir -p "$proj/infra/local" && touch "$proj/infra/local/docker-compose.yml"
check "up"   0 "" compose "up -d --wait" -- up
check "down" 0 "" compose "up -d --wait
down -v" -- down

# check: runs every step and fails when any one fails.
fresh
check "check passes"            0 "" golangci-lint "run ./..." -- check
check "check runs go test"      0 "" go "test -race ./...
test -race ./..." -- check
fresh
FAKE_FAIL=golangci-lint \
  check "check, lint fails"     fail "" - "" -- check
fresh
FAKE_FAIL=go \
  check "check, test fails"     fail "" - "" -- check
fresh
printf '#!/usr/bin/env bash\nexit 1\n' >"$proj/scripts/broken_test.sh"
check "check, script test fails" fail "broken_test.sh" - "" -- check
fresh
printf '#!/usr/bin/env bash\nexit 1\n' >"$proj/.claude/hooks/hooks_test.sh"
check "check, hooks test fails"  fail "hooks_test.sh" - "" -- check

echo "makefile: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
