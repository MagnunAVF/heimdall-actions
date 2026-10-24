//go:build integration

// Package keycloak_test checks the heimdall realm (infra/local/keycloak) against the Keycloak
// started by `make up`: it logs the dev users in through the authorization code flow with PKCE,
// as the web app does, and inspects the access tokens. KEYCLOAK_URL overrides the default
// http://localhost:8080.
package keycloak_test

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"html"
	"io"
	"net/http"
	"net/http/cookiejar"
	"net/url"
	"os"
	"regexp"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const (
	clientID    = "heimdall-web"
	redirectURI = "http://localhost:5173/callback"
)

// loginAction finds the login form's target in Keycloak's login page.
var loginAction = regexp.MustCompile(`action="([^"]*/login-actions/authenticate[^"]*)"`)

func realmURL() string {
	base := os.Getenv("KEYCLOAK_URL")
	if base == "" {
		base = "http://localhost:8080"
	}
	return strings.TrimSuffix(base, "/") + "/realms/heimdall"
}

// audience is the aud claim, which Keycloak sends as a string or an array.
type audience []string

func (a *audience) UnmarshalJSON(b []byte) error {
	var one string
	if err := json.Unmarshal(b, &one); err == nil {
		*a = audience{one}
		return nil
	}
	var many []string
	if err := json.Unmarshal(b, &many); err != nil {
		return err
	}
	*a = many
	return nil
}

type claims struct {
	Iss         string   `json:"iss"`
	Aud         audience `json:"aud"`
	Azp         string   `json:"azp"`
	RealmAccess struct {
		Roles []string `json:"roles"`
	} `json:"realm_access"`
}

type tokenResponse struct {
	AccessToken string `json:"access_token"`
	Error       string `json:"error"`
	Description string `json:"error_description"`
}

func TestDiscoveryIssuer(t *testing.T) {
	var doc struct {
		Issuer string `json:"issuer"`
	}
	resp := get(t, http.DefaultClient, realmURL()+"/.well-known/openid-configuration")
	defer func() { require.NoError(t, resp.Body.Close()) }()
	require.Equal(t, http.StatusOK, resp.StatusCode)
	require.NoError(t, json.NewDecoder(resp.Body).Decode(&doc))

	assert.Equal(t, realmURL(), doc.Issuer)
}

func TestLoginTokenClaims(t *testing.T) {
	tests := []struct {
		user     string
		password string
		roles    []string
		notRoles []string
	}{
		{user: "alice", password: "alice", roles: []string{"admin", "developer"}},
		{user: "bob", password: "bob", roles: []string{"developer"}, notRoles: []string{"admin"}},
	}
	for _, tt := range tests {
		t.Run(tt.user, func(t *testing.T) {
			code, verifier := login(t, tt.user, tt.password)
			status, tok := exchange(t, code, verifier)
			require.Equal(t, http.StatusOK, status, "token error: %s %s", tok.Error, tok.Description)

			c := decode(t, tok.AccessToken)
			assert.Equal(t, realmURL(), c.Iss)
			assert.Contains(t, []string(c.Aud), "heimdall-api")
			assert.Equal(t, clientID, c.Azp)
			for _, r := range tt.roles {
				assert.Contains(t, c.RealmAccess.Roles, r)
			}
			for _, r := range tt.notRoles {
				assert.NotContains(t, c.RealmAccess.Roles, r)
			}
		})
	}
}

func TestPasswordGrantRefused(t *testing.T) {
	status, tok := postToken(t, url.Values{
		"grant_type": {"password"},
		"client_id":  {clientID},
		"username":   {"alice"},
		"password":   {"alice"},
	})

	assert.GreaterOrEqual(t, status, http.StatusBadRequest)
	assert.Equal(t, "unauthorized_client", tok.Error)
	assert.Empty(t, tok.AccessToken)
}

func TestCodeExchangeWithoutVerifierRefused(t *testing.T) {
	code, _ := login(t, "bob", "bob")
	status, tok := exchange(t, code, "")

	assert.Equal(t, http.StatusBadRequest, status)
	assert.Equal(t, "invalid_grant", tok.Error)
	assert.Empty(t, tok.AccessToken)
}

// login runs the browser part of the authorization code flow with PKCE and returns the code
// and the verifier. The redirect to the web app is captured, not followed.
func login(t *testing.T, user, password string) (code, verifier string) {
	t.Helper()
	jar, err := cookiejar.New(nil)
	require.NoError(t, err)
	client := &http.Client{
		Jar: jar,
		CheckRedirect: func(req *http.Request, _ []*http.Request) error {
			if strings.HasPrefix(req.URL.String(), redirectURI) {
				return http.ErrUseLastResponse
			}
			return nil
		},
	}

	b := make([]byte, 32)
	_, err = rand.Read(b)
	require.NoError(t, err)
	verifier = base64.RawURLEncoding.EncodeToString(b)
	sum := sha256.Sum256([]byte(verifier))

	resp := get(t, client, realmURL()+"/protocol/openid-connect/auth?"+url.Values{
		"client_id":             {clientID},
		"response_type":         {"code"},
		"scope":                 {"openid"},
		"redirect_uri":          {redirectURI},
		"state":                 {"integration-test"},
		"code_challenge":        {base64.RawURLEncoding.EncodeToString(sum[:])},
		"code_challenge_method": {"S256"},
	}.Encode())
	page, err := io.ReadAll(resp.Body)
	require.NoError(t, resp.Body.Close())
	require.NoError(t, err)
	require.Equal(t, http.StatusOK, resp.StatusCode, "login page: %s", page)
	m := loginAction.FindSubmatch(page)
	require.NotNil(t, m, "no login form in the login page")

	resp = post(t, client, html.UnescapeString(string(m[1])), url.Values{
		"username": {user},
		"password": {password},
	})
	require.NoError(t, resp.Body.Close())
	require.Equal(t, http.StatusFound, resp.StatusCode, "login did not redirect to the web app")
	loc, err := url.Parse(resp.Header.Get("Location"))
	require.NoError(t, err)
	require.Equal(t, "integration-test", loc.Query().Get("state"))
	code = loc.Query().Get("code")
	require.NotEmpty(t, code, "no code in redirect %s", loc)
	return code, verifier
}

// exchange trades a code for tokens; an empty verifier leaves code_verifier out.
func exchange(t *testing.T, code, verifier string) (int, tokenResponse) {
	t.Helper()
	form := url.Values{
		"grant_type":   {"authorization_code"},
		"client_id":    {clientID},
		"code":         {code},
		"redirect_uri": {redirectURI},
	}
	if verifier != "" {
		form.Set("code_verifier", verifier)
	}
	return postToken(t, form)
}

func postToken(t *testing.T, form url.Values) (int, tokenResponse) {
	t.Helper()
	resp := post(t, http.DefaultClient, realmURL()+"/protocol/openid-connect/token", form)
	defer func() { require.NoError(t, resp.Body.Close()) }()
	var tok tokenResponse
	require.NoError(t, json.NewDecoder(resp.Body).Decode(&tok))
	return resp.StatusCode, tok
}

// decode reads a JWT's payload without checking its signature; the API's middleware does that.
func decode(t *testing.T, jwt string) claims {
	t.Helper()
	parts := strings.Split(jwt, ".")
	require.Len(t, parts, 3, "access token is not a JWT")
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	require.NoError(t, err)
	var c claims
	require.NoError(t, json.Unmarshal(payload, &c))
	return c
}

func get(t *testing.T, client *http.Client, u string) *http.Response {
	t.Helper()
	req, err := http.NewRequestWithContext(t.Context(), http.MethodGet, u, nil)
	require.NoError(t, err)
	return do(t, client, req)
}

func post(t *testing.T, client *http.Client, u string, form url.Values) *http.Response {
	t.Helper()
	req, err := http.NewRequestWithContext(t.Context(), http.MethodPost, u, strings.NewReader(form.Encode()))
	require.NoError(t, err)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	return do(t, client, req)
}

func do(t *testing.T, client *http.Client, req *http.Request) *http.Response {
	t.Helper()
	resp, err := client.Do(req)
	var uerr *url.Error
	if errors.As(err, &uerr) && strings.Contains(uerr.Err.Error(), "connection refused") {
		t.Fatalf("Keycloak not reachable at %s: run `make up` first", realmURL())
	}
	require.NoError(t, err)
	return resp
}
