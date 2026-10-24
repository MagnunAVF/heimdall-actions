# ENG-5: Docker Compose stack: PostgreSQL, Redis, Keycloak (plan 1.1a)

Status: approved 2026-10-24. Milestone M1, lane deploy.

## Goal

Add `deploy/docker-compose.yml` with PostgreSQL, Redis and Keycloak for local development, with
pinned images, healthchecks, named volumes and no committed secrets, plus `deploy/.env.example`.
`make up` / `make down` (already in the ENG-4 Makefile) start and remove the stack. Acceptance:
M1 exit criterion 3, except the realm (ENG-6).

## Public API

Compose project `heimdall` (set by the Makefile). Every port is published on `127.0.0.1` only.

| Service | Image | Host port | Healthcheck | Volume |
|---|---|---|---|---|
| `postgres` | `postgres:17.11-alpine` | `${POSTGRES_PORT:-5432}` | `pg_isready` | `postgres-data` |
| `redis` | `redis:8.10.2-alpine` | `${REDIS_PORT:-6379}` | `redis-cli ping` (with auth) | `redis-data` |
| `keycloak` | `quay.io/keycloak/keycloak:26.8.1` (`start-dev`) | `${KEYCLOAK_PORT:-8080}` | `/health/ready` on 9000 via bash `/dev/tcp` | `keycloak-data` |

Variables, each with a dev-only default `${VAR:-default}` and documented in
`deploy/.env.example`: `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` (all `heimdall`),
`POSTGRES_PORT`, `REDIS_PASSWORD` (`heimdall`), `REDIS_PORT`, `KC_BOOTSTRAP_ADMIN_USERNAME`,
`KC_BOOTSTRAP_ADMIN_PASSWORD` (`admin`/`admin`), `KEYCLOAK_PORT`.

Resulting dev DSNs: `postgres://heimdall:heimdall@localhost:5432/heimdall?sslmode=disable`,
`redis://:heimdall@localhost:6379/0`, Keycloak at `http://localhost:8080`.

## Tests

`scripts/compose_test.sh` (run by `make check` through `script-tests`): static checks on
`docker compose config --format json` with `jq`. Needs the docker CLI, not a running daemon.

| # | Case | Expected |
|---|---|---|
| 1 | Valid with no `.env` | `docker compose config -q` exits 0 |
| 2 | Service set | exactly `postgres`, `redis`, `keycloak` |
| 3 | Pinned images | `postgres:17.N[.N]`, `redis:8.N.N`, `quay.io/keycloak/keycloak:26.N.N` (optional `-alpine`) |
| 4 | Healthchecks | every service has `healthcheck.test` |
| 5 | Named volumes | every service mounts a `type: volume` declared at top level; no bind mounts |
| 6 | No literal secrets | every `*PASSWORD*` value in the raw file is `${VAR:-...}` |
| 7 | Defaults documented | variables in the compose file and `.env.example` match both ways |
| 8 | Overrides work | `POSTGRES_PASSWORD=x` shows up in the rendered config |
| 9 | Local-only ports | every published port has `host_ip: 127.0.0.1` |
| 10 | Checker can fail | a fixture with `postgres:latest` and no healthcheck fails the checks |

Manual (needs the daemon): `make up` shows all three healthy in `docker compose ps`; `make down`
removes containers and volumes (`docker volume ls`). Output goes in the PR.

## Tasks

1. Docs: this plan and the M1 Decisions lines.
2. `scripts/compose_test.sh` (failing first), then `deploy/docker-compose.yml` and
   `deploy/.env.example`; `make check` green; manual `make up` / `make down`.

## Approved decisions

- Keycloak uses the `start-dev` file database in the `keycloak-data` volume, not Postgres.
- The test lives in `scripts/compose_test.sh` (ci lane, test-only file) so `make check` runs it.
- Redis requires a password (`--requirepass`), for parity with production.
- Postgres and Redis use the `-alpine` images.
- `compose_test.sh` fails, not skips, when the docker CLI is missing.
