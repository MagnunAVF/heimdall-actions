#!/usr/bin/env bash
# Static checks on the Keycloak realm in infra/local/keycloak: the heimdall-web client (public,
# standard flow only, PKCE S256, local redirects), the heimdall-api audience mapper, realm roles,
# dev users, the README, and the Compose import of the realm file. Every check is first run on a
# bad fixture (it must complain), then on the real files (it must not). Renders the Compose file
# with `docker compose config`, so it needs the docker CLI but not a running daemon.
# Run: bash scripts/realm_test.sh
set -u

here=$(cd "$(dirname "$0")" && pwd)
stack="$here/../infra/local"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  echo "FAIL realm: docker compose CLI not found"
  echo "realm: 0 passed, 1 failed"
  exit 1
fi

import_path=/opt/keycloak/data/import/heimdall-realm.json

# Each check_* takes a dir laid out like infra/local (docker-compose.yml, keycloak/heimdall-realm.json,
# keycloak/README.md) and prints one line per problem; no output means the check passed.

# realm <dir> <jq filter>: runs the filter on the realm file, or complains if it is not JSON.
# The filter can refer to the whole document as $root.
realm() {
  jq -r ". as \$root | $2" "$1/keycloak/heimdall-realm.json" 2>/dev/null ||
    echo "realm file missing or not JSON"
}

# web <dir> <jq filter>: runs the filter on the heimdall-web client.
web() {
  realm "$1" '[.clients[]? | select(.clientId == "heimdall-web")] as $c
    | if ($c | length) != 1 then "heimdall-web: want 1 client, got \($c | length)"
      else $c[0] | '"$2"' end'
}

check_json() {
  jq empty "$1/keycloak/heimdall-realm.json" >/dev/null 2>&1 || echo "realm file missing or not JSON"
}

check_realm() {
  realm "$1" '(if .realm != "heimdall" then "realm: got \(.realm) want heimdall" else empty end),
    (if .enabled != true then "realm: not enabled" else empty end),
    (if .registrationAllowed != false then "realm: registration not off" else empty end)'
}

check_client_flows() {
  web "$1" '(if .publicClient != true then "heimdall-web: not public" else empty end),
    (if .standardFlowEnabled != true then "heimdall-web: standard flow off" else empty end),
    (if .directAccessGrantsEnabled != false then "heimdall-web: direct access grants not off" else empty end),
    (if .implicitFlowEnabled != false then "heimdall-web: implicit flow not off" else empty end),
    (if .serviceAccountsEnabled != false then "heimdall-web: service accounts not off" else empty end)'
}

check_pkce() {
  web "$1" 'if .attributes["pkce.code.challenge.method"] != "S256"
    then "heimdall-web: PKCE method is not S256" else empty end'
}

check_redirects() {
  web "$1" '(if .redirectUris != ["http://localhost:5173/*"]
      then "heimdall-web: redirectUris \(.redirectUris) want [http://localhost:5173/*]" else empty end),
    (if .webOrigins != ["http://localhost:5173"]
      then "heimdall-web: webOrigins \(.webOrigins) want [http://localhost:5173]" else empty end),
    (if .attributes["post.logout.redirect.uris"] != "http://localhost:5173/*"
      then "heimdall-web: post-logout redirect is not http://localhost:5173/*" else empty end)'
}

check_audience() {
  web "$1" '[.protocolMappers[]? | select(.protocolMapper == "oidc-audience-mapper")] as $m
    | if ($m | length) != 1 then "heimdall-web: want 1 audience mapper, got \($m | length)"
      else $m[0].config
        | (if .["included.custom.audience"] != "heimdall-api"
            then "audience mapper: custom audience is not heimdall-api" else empty end),
          (if .["access.token.claim"] != "true"
            then "audience mapper: not added to the access token" else empty end)
      end'
}

check_no_api_client() {
  realm "$1" '.clients[]? | (select(.clientId == "heimdall-api") | "client heimdall-api must not exist"),
    (select(has("secret")) | "client \(.clientId) has a secret")'
}

check_roles() {
  realm "$1" '[.roles.realm[]?.name] as $r | ("admin", "developer")
    | select(. as $want | $r | index($want) | not) | "realm role missing: \(.)"'
}

check_users() {
  realm "$1" '{"alice": ["admin", "developer"], "bob": ["developer"]} | to_entries[] as $want
    | [$root.users[]? | select(.username == $want.key)] as $u
    | if ($u | length) != 1 then "user \($want.key): want 1, got \($u | length)" else $u[0] |
        (if .enabled != true then "user \(.username): not enabled" else empty end),
        (if .emailVerified != true then "user \(.username): email not verified" else empty end),
        (if ((.email // "") == "" or (.firstName // "") == "" or (.lastName // "") == "")
          then "user \(.username): email, firstName or lastName missing" else empty end),
        (if (.requiredActions // []) != [] then "user \(.username): has required actions" else empty end),
        (if ((.realmRoles // []) | sort) != ($want.value | sort)
          then "user \(.username): roles \(.realmRoles) want \($want.value)" else empty end),
        (if [.credentials[]? | select(.type == "password" and .temporary == false)] | length != 1
          then "user \(.username): want 1 non-temporary password" else empty end)
      end'
}

check_documented() {
  local readme="$1/keycloak/README.md" user
  [ -f "$readme" ] || { echo "keycloak/README.md missing"; return; }
  for user in $(realm "$1" '.users[]?.username'); do
    grep -qw -- "$user" "$readme" || echo "user $user not in keycloak/README.md"
  done
}

check_compose_import() {
  local out="$1/rendered.json"
  env -i PATH="$PATH" HOME="$HOME" ${DOCKER_HOST:+DOCKER_HOST="$DOCKER_HOST"} \
    docker compose -p heimdall-test -f "$1/docker-compose.yml" --env-file /dev/null \
    config --format json >"$out" 2>/dev/null || { echo "docker compose config failed"; return; }
  jq -r --arg target "$import_path" '. as $root | .services.keycloak as $kc
    | (if ($kc.command // [] | index("--import-realm")) == null
        then "keycloak: command has no --import-realm" else empty end),
      ([$kc.configs[]? | select(.target == $target)
        | $root.configs[.source].file // "" | select(endswith("/keycloak/heimdall-realm.json"))]
        | if length != 1 then "keycloak: realm file not mounted at \($target)" else empty end)' "$out"
}

checks="check_json check_realm check_client_flows check_pkce check_redirects check_audience
check_no_api_client check_roles check_users check_documented check_compose_import"

bad="$tmp/bad"
mkdir -p "$bad/keycloak"
cat >"$bad/keycloak/heimdall-realm.json" <<'EOF'
{
  "realm": "master",
  "registrationAllowed": true,
  "roles": {"realm": [{"name": "user"}]},
  "clients": [
    {"clientId": "heimdall-web", "publicClient": false, "secret": "s3cret",
     "directAccessGrantsEnabled": true, "redirectUris": ["*"], "webOrigins": ["*"]},
    {"clientId": "heimdall-api", "bearerOnly": true}
  ],
  "users": [
    {"username": "alice", "enabled": true, "realmRoles": ["user"], "requiredActions": ["UPDATE_PROFILE"],
     "credentials": [{"type": "password", "value": "x", "temporary": true}]},
    {"username": "mallory", "enabled": true}
  ]
}
EOF
printf '# Realm\n\nNo users documented.\n' >"$bad/keycloak/README.md"
cat >"$bad/docker-compose.yml" <<'EOF'
services:
  keycloak:
    image: quay.io/keycloak/keycloak:26.8.1
    command: start-dev
EOF
# A realm file that is not JSON, for check_json.
broken="$tmp/broken"
mkdir -p "$broken/keycloak"
printf '{"realm": \n' >"$broken/keycloak/heimdall-realm.json"

pass=0 fail=0
for c in $checks; do
  dir=$bad
  [ "$c" = check_json ] && dir=$broken
  if [ -n "$($c "$dir")" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); echo "FAIL fixture $c: no problem reported for the bad fixture"
  fi
done

real="$tmp/real"
mkdir -p "$real/keycloak"
[ -f "$stack/docker-compose.yml" ] && cp "$stack/docker-compose.yml" "$real/"
for f in heimdall-realm.json README.md; do
  [ -f "$stack/keycloak/$f" ] && cp "$stack/keycloak/$f" "$real/keycloak/"
done
for c in $checks; do
  if out=$($c "$real" 2>&1); [ -z "$out" ]; then pass=$((pass + 1)); else
    fail=$((fail + 1)); printf 'FAIL %s:\n%s\n' "$c" "$out"
  fi
done

echo "realm: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
