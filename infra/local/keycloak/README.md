# Keycloak realm `heimdall` (local development)

`heimdall-realm.json` is imported when the `keycloak` service in `../docker-compose.yml` starts
(`start-dev --import-realm`). Keycloak skips the import if the realm already exists in the
`keycloak-data` volume, so `make down && make up` is what resets the realm to this file.

- Issuer: `http://localhost:8080/realms/heimdall`
- Discovery: `http://localhost:8080/realms/heimdall/.well-known/openid-configuration`
- Admin console: `http://localhost:8080/admin` (`admin` / `admin`, see `../.env.example`)

## Client

`heimdall-web` is the web app's public client: authorization code flow only, PKCE `S256`
required, redirect `http://localhost:5173/*`, web origin `http://localhost:5173`. Direct access
grants (password grant) are off. An audience mapper adds `heimdall-api` to the access token's
`aud`; the API checks that audience, and there is no separate API client.

## Dev users

Dev-only credentials. They exist only in this local realm; never reuse them anywhere else.

| Username | Password | Realm roles |
|---|---|---|
| `alice` | `alice` | `admin`, `developer` |
| `bob` | `bob` | `developer` |

## Changing the realm

Changes made in the admin console are lost on `make down`. To keep one, make it in the console,
export it (Realm settings → Action → Partial export, which leaves out users) and copy only the
part you changed into `heimdall-realm.json`. Keep the file minimal (no generated ids or default scopes) and run `bash scripts/realm_test.sh`.
The integration test in `test/integration/keycloak` checks a real login against the running
stack: `make up && make test-integration`.
