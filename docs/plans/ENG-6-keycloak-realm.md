# ENG-6: Keycloak realm, clients and dev users (plan 1.1b)

Status: approved 2026-10-24. Milestone M1, lane deploy.

## Goal

Add the `heimdall` realm export at `infra/local/keycloak/heimdall-realm.json` (the issue's
`deploy/` paths predate the ENG-5 rename), imported when Keycloak starts, with the `heimdall-web`
client, the `heimdall-api` audience, realm roles and two dev users. `make down && make up` yields
the same realm. Acceptance: M1 exit criterion 4.

## Public API

Realm `heimdall`: enabled, `sslRequired: external`, registration off, brute-force protection on,
default token lifespans. Issuer `http://localhost:8080/realms/heimdall`.

| Object | Settings |
|---|---|
| Client `heimdall-web` | public; standard flow only (direct access grants, implicit, service accounts off); PKCE `S256`; redirect `http://localhost:5173/*`; web origin `http://localhost:5173`; post-logout redirect `http://localhost:5173/*` |
| Mapper on `heimdall-web` | `oidc-audience-mapper`, custom audience `heimdall-api`, access token only. No `heimdall-api` client |
| Realm roles | `admin`, `developer` (in `realm_access.roles` through the default `roles` scope) |
| User `alice` / `alice` | roles `admin`, `developer` |
| User `bob` / `bob` | role `developer` |

Users have email, first and last name and `emailVerified: true`, so Keycloak 26 asks for no
profile update at login. Passwords are dev-only and not temporary.

Compose (`keycloak` service): command `start-dev --import-realm`; the realm file is a top-level
Compose config (`configs: heimdall-realm: file: ./keycloak/heimdall-realm.json`) mounted read-only
at `/opt/keycloak/data/import/heimdall-realm.json`. `make down` drops `keycloak-data`, so the next
`make up` re-imports the file.

`infra/local/keycloak/README.md`: users, passwords, roles, issuer, and how to change the realm
(edits in the admin console are lost on `make down`; export and commit the JSON instead).

## Tests

`scripts/realm_test.sh` (run by `make check`; jq and the docker CLI, no daemon). Every check must
complain about a bad fixture, then pass on the real files.

| # | Case | Expected |
|---|---|---|
| 1 | Valid JSON, realm | `.realm == "heimdall"`, enabled |
| 2 | `heimdall-web` public, standard flow only | `publicClient`, `standardFlowEnabled`; direct grants, implicit, service accounts false |
| 3 | PKCE | `pkce.code.challenge.method == "S256"` |
| 4 | Redirects and origins | redirect URIs exactly `http://localhost:5173/*`, web origins exactly `http://localhost:5173` |
| 5 | Audience mapper | one `oidc-audience-mapper`, custom audience `heimdall-api`, `access.token.claim` true |
| 6 | No API client, no secrets | no `heimdall-api` client; no client `secret` |
| 7 | Realm roles | `admin` and `developer` |
| 8 | Dev users | `alice` admin+developer, `bob` developer; enabled, email verified, no required actions, non-temporary passwords |
| 9 | Users documented | every username appears in the README |
| 10 | Compose imports the realm | rendered Keycloak command has `--import-realm`; the realm file is mounted at the import path |
| 11 | Checker can fail | a confidential, no-PKCE, direct-grant fixture fails every check |

`test/integration/keycloak/realm_test.go` (`//go:build integration`, needs `make up`, stdlib and
testify only; `KEYCLOAK_URL` defaults to `http://localhost:8080`):

| # | Case | Expected |
|---|---|---|
| 1 | Discovery | 200; `issuer` is `${KEYCLOAK_URL}/realms/heimdall` |
| 2 | `alice` via authorization code + PKCE | `iss` is the issuer; `aud` contains `heimdall-api`; `azp` is `heimdall-web`; roles admin and developer |
| 3 | `bob` | `aud` contains `heimdall-api`; developer, not admin |
| 4 | Password grant | refused (`unauthorized_client`): standard flow only |
| 5 | Code exchange without a verifier | refused: PKCE enforced |

The test drives the login form (cookie jar, form action from the login page, redirect to
`localhost:5173` captured, not followed) and decodes the JWT payload without verifying the
signature (ENG-8 does that). Manual: `make down && make up` then the integration test, twice;
output in the PR.

## Tasks

1. Docs: this plan and the M1 Decisions lines.
2. `scripts/realm_test.sh` (failing first), then the realm JSON, the README and the Compose
   change; `make check` green.
3. `test/integration/keycloak/realm_test.go`, run against `make up`, including down/up twice.

## Approved decisions

- 2026-10-24: The realm file reaches Keycloak as a read-only Compose `config`, not a bind mount
  under `volumes`, so `compose_test.sh` (named volumes only, for data) is unchanged.
- 2026-10-24: The integration test gets tokens through the real authorization code + PKCE flow;
  `heimdall-web` keeps direct access grants off and there is no test-only client.
- 2026-10-24: Dev users `alice`/`alice` (admin, developer) and `bob`/`bob` (developer).
- 2026-10-24: Cross-component integration tests live under `test/integration/<component>/`, not
  in `infra/` (infra holds only infrastructure). `test/integration/keycloak/` belongs to the
  deploy lane.
