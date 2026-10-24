#!/usr/bin/env bash
# Static checks on infra/local/docker-compose.yml and infra/local/.env.example: the service set, pinned
# images, healthchecks, named volumes, local-only ports and no committed secrets. Every check is
# first run on a bad fixture (it must complain), then on the real files (it must not). Renders the
# file with `docker compose config`, so it needs the docker CLI but not a running daemon.
# Run: bash scripts/compose_test.sh
set -u

here=$(cd "$(dirname "$0")" && pwd)
stack="$here/../infra/local"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  echo "FAIL compose: docker compose CLI not found"
  echo "compose: 0 passed, 1 failed"
  exit 1
fi

# render <dir> [env-file]: writes <dir>/rendered.json, ignoring any .env and the caller's env.
render() {
  local env_file=${2:-$tmp/empty.env}
  : >"$tmp/empty.env"
  env -i PATH="$PATH" HOME="$HOME" ${DOCKER_HOST:+DOCKER_HOST="$DOCKER_HOST"} \
    docker compose -p heimdall-test -f "$1/docker-compose.yml" --env-file "$env_file" \
    config --format json >"$1/rendered.json" 2>"$1/render.err"
}

# Each check_* takes a dir with docker-compose.yml and .env.example and prints one line per
# problem; no output means the check passed.
check_valid() {
  render "$1" || { echo "docker compose config failed: $(cat "$1/render.err")"; return; }
  [ -s "$1/rendered.json" ] || echo "docker compose config printed nothing"
}

# json <dir> <jq filter>: runs the filter on the rendered config, or complains if there is none.
json() {
  if [ -s "$1/rendered.json" ]; then jq -r "$2" "$1/rendered.json"; else echo "not rendered"; fi
}

check_services() {
  local got
  got=$(json "$1" '.services | keys | join(",")')
  [ "$got" = "keycloak,postgres,redis" ] || echo "services: got $got want keycloak,postgres,redis"
}

check_images() {
  json "$1" '.services | to_entries[] | "\(.key) \(.value.image // "")"' | while read -r svc img; do
    case $svc in
    postgres) re='^postgres:17\.[0-9]+(\.[0-9]+)?(-alpine)?$' ;;
    redis) re='^redis:8\.[0-9]+\.[0-9]+(-alpine)?$' ;;
    keycloak) re='^quay\.io/keycloak/keycloak:26\.[0-9]+\.[0-9]+$' ;;
    *) re='^$' ;;
    esac
    [[ "$img" =~ $re ]] || echo "image not pinned: $svc $img"
  done
}

check_healthchecks() {
  json "$1" '.services | to_entries[]
    | select((.value.healthcheck.test // []) | length == 0 or .[0] == "NONE") | .key' |
    sed 's/^/no healthcheck: /'
}

check_volumes() {
  json "$1" '(.volumes // {} | keys) as $named | .services | to_entries[]
    | .key as $svc | (.value.volumes // []) as $v
    | if ($v | map(select(.type == "volume" and (.source as $s | $named | index($s)))) | length) == 0
      then "no named volume: \($svc)" else empty end,
      ($v[] | select(.type != "volume") | "not a named volume: \($svc) \(.type) \(.source)")'
}

check_ports() {
  json "$1" '.services | to_entries[] | .key as $svc | (.value.ports // [])[]
    | select(.host_ip != "127.0.0.1") | "port not bound to 127.0.0.1: \($svc) \(.published)"'
}

# Raw-file checks: interpolation is gone once rendered.
check_no_literal_secrets() {
  grep -nE '^[[:space:]-]*[A-Z_]*PASSWORD[A-Z_]*[[:space:]]*[:=]' "$1/docker-compose.yml" |
    grep -vE '[:=][[:space:]]*"?\$\{[A-Z_][A-Z0-9_]*:-[^}]*\}"?[[:space:]]*$' |
    sed 's/^/literal password: /'
  grep -nE 'requirepass[[:space:]]+[^$[:space:]]' "$1/docker-compose.yml" |
    sed 's/^/literal password: /'
}

check_vars_documented() {
  local used documented
  used=$(grep -oE '(^|[^$])\$\{[A-Za-z_][A-Za-z0-9_]*[^}]*\}' "$1/docker-compose.yml" |
    sed -E 's/^[^$]?\$\{//; s/\}$//')
  printf '%s\n' "$used" | grep -vE '^$' | grep -vE '^[A-Za-z_][A-Za-z0-9_]*:-' |
    sed 's/^/no default: /'
  used=$(printf '%s\n' "$used" | sed -E 's/[^A-Za-z0-9_].*$//' | grep -vE '^$' | sort -u)
  documented=$(sed -nE 's/^#?[[:space:]]*([A-Z_][A-Z0-9_]*)=.*/\1/p' "$1/.env.example" 2>/dev/null |
    sort -u)
  comm -23 <(printf '%s\n' "$used") <(printf '%s\n' "$documented") | grep -vE '^$' |
    sed 's/^/not in .env.example: /'
  comm -13 <(printf '%s\n' "$used") <(printf '%s\n' "$documented") | grep -vE '^$' |
    sed 's/^/unused in docker-compose.yml: /'
}

check_override() {
  mkdir -p "$1/override"
  cp "$1/docker-compose.yml" "$1/override/"
  printf 'POSTGRES_PASSWORD=override-x\n' >"$tmp/override.env"
  render "$1/override" "$tmp/override.env" || { echo "override: render failed"; return; }
  [ "$(json "$1/override" '.services.postgres.environment.POSTGRES_PASSWORD // ""')" = override-x ] ||
    echo "override: POSTGRES_PASSWORD from the env file did not reach postgres"
}

checks="check_valid check_services check_images check_healthchecks check_volumes check_ports
check_no_literal_secrets check_vars_documented check_override"

bad="$tmp/bad"
mkdir -p "$bad"
cat >"$bad/docker-compose.yml" <<'EOF'
services:
  postgres:
    image: postgres:latest
    environment:
      POSTGRES_PASSWORD: secret
    ports: ["5432:5432"]
    volumes: ["./data:/var/lib/postgresql/data"]
  rabbitmq:
    image: rabbitmq:${RABBIT_TAG}
    command: redis-server --requirepass secret
EOF
printf 'UNUSED=1\n' >"$bad/.env.example"
# A compose file docker cannot parse, for check_valid.
broken="$tmp/broken"
mkdir -p "$broken"
printf 'services: [\n' >"$broken/docker-compose.yml"
: >"$broken/.env.example"

pass=0 fail=0
for c in $checks; do
  dir=$bad
  [ "$c" = check_valid ] && dir=$broken
  [ "$c" = check_valid ] || check_valid "$bad" >/dev/null
  if [ -n "$($c "$dir")" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); echo "FAIL fixture $c: no problem reported for the bad fixture"
  fi
done

real="$tmp/real"
mkdir -p "$real"
if [ -f "$stack/docker-compose.yml" ]; then cp "$stack/docker-compose.yml" "$real/"; fi
if [ -f "$stack/.env.example" ]; then cp "$stack/.env.example" "$real/"; fi
if [ -f "$real/docker-compose.yml" ]; then pass=$((pass + 1)); else
  fail=$((fail + 1)); echo "FAIL infra/local/docker-compose.yml not found"
fi
for c in $checks; do
  [ "$c" = check_valid ] || check_valid "$real" >/dev/null
  if out=$($c "$real" 2>&1); [ -z "$out" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL %s:\n%s\n' "$c" "$out"
  fi
done

echo "compose: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
