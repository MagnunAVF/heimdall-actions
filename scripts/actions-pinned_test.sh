#!/usr/bin/env bash
# Checks that every action in .github/workflows is pinned to a full commit SHA with the version in
# a comment ("uses: owner/repo@<40 hex> # vX.Y.Z"). Local actions (./path) need no pin. The
# detector is first checked against fixtures, then run on the real workflows.
# Run: bash scripts/actions-pinned_test.sh
set -u

here=$(cd "$(dirname "$0")" && pwd)
workflows="$here/../.github/workflows"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# unpinned <dir>: prints file:line:text for every remote `uses:` that is not pinned.
unpinned() {
  grep -HnE '^[[:space:]-]*uses:' "$1"/*.yml "$1"/*.yaml 2>/dev/null |
    grep -vE 'uses:[[:space:]]+\./' |
    grep -vE 'uses:[[:space:]]+[^@[:space:]]+@[0-9a-f]{40}[[:space:]]+#[[:space:]]*v[0-9]'
}

pass=0 fail=0
# fixture <name> <want: pinned|unpinned> <uses line>
fixture() {
  local name=$1 want=$2 line=$3 got=pinned
  mkdir -p "$tmp/$name"
  printf 'jobs:\n  x:\n    steps:\n%s\n' "$line" >"$tmp/$name/w.yml"
  [ -n "$(unpinned "$tmp/$name")" ] && got=unpinned
  if [ "$got" = "$want" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); echo "FAIL fixture $name: got $got want $want ($line)"
  fi
}

sha=11d5960a326750d5838078e36cf38b85af677262
fixture sha-and-version  pinned   "      - uses: actions/checkout@$sha # v4.4.0"
fixture subpath          pinned   "      - uses: github/codeql-action/init@$sha # v3.29.0"
fixture local-action     pinned   "      - uses: ./.github/actions/setup"
fixture reusable-wf      pinned   "    uses: o/r/.github/workflows/x.yml@$sha # v1"
fixture tag              unpinned "      - uses: actions/checkout@v4"
fixture branch           unpinned "      - uses: actions/checkout@main"
fixture short-sha        unpinned "      - uses: actions/checkout@11d5960 # v4.4.0"
fixture no-comment       unpinned "      - uses: actions/checkout@$sha"
fixture comment-no-ver   unpinned "      - uses: actions/checkout@$sha # pinned"
fixture no-ref           unpinned "      - uses: actions/checkout"
fixture docker           unpinned "      - uses: docker://alpine:3"

if ls "$workflows"/*.yml >/dev/null 2>&1; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL no workflows found in $workflows"
fi
if bad=$(unpinned "$workflows"); [ -z "$bad" ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); printf 'FAIL unpinned actions:\n%s\n' "$bad"
fi

echo "actions-pinned: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
