# PM + ZD Basic Setup

This docker compose is indented to illustrate general direction of how PM
(Papermerge) is supposed to interact with ZD (Zitadel). The setup
is very basic and it holds more educational character than ready to use recipe.

## Setup

Create an `.env`
Login into ZD:

Browser address: http://localhost:8080/
with username: `root@my-organization.localhost`
password: `AdminPassword123!`

## Configure Zitadel Application

1. **Access Zitadel Console:**
```
   http://localhost:8080/ui/console

Login:

Username: root@my-organization.localhost
Password: AdminPassword123!


Create Project:

Click Projects → Create New Project
Name: Papermerge
Click Continue


Create Application:

Click on your project → New Application
Name: Papermerge OAuth2-Proxy
Type: Web
Authentication Method: Code (with PKCE recommended)
Click Continue


Configure Redirect URIs:

Redirect URI: http://localhost:8081/oauth2/callback
Post Logout URI: http://localhost:8081
Click Continue


Review and Create
Copy Credentials:
```

You'll see the Client ID and Client Secret (only shown once!)
Save them immediately!

## Replace with actual values from Zitadel

`
ZITADEL_CLIENT_ID=353636209450343469  # Your actual Client ID
ZITADEL_CLIENT_SECRET=abc123xyz789...  # Your actual Client Secret
`

## Generate cookie secret if you haven't

`
OAUTH2_COOKIE_SECRET=your-32-char-random-secret-here
`


##  Make User a Superuser in Papermerge

`
docker compose exec db psql -U postgres -d pmdb
`

`
UPDATE users
SET is_superuser = true
WHERE username = '355901215668240388';   # whatever was created in DB (excluding systemuser)
`


# Complete HTTP Request Flow Diagram

## Papermerge + OAuth2-Proxy + Zitadel

---

## Network Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Docker Network: zitadel                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         Shared Network Namespace                         │  │
│  │         (zitadel container)                              │  │
│  ├──────────────────────────────────────────────────────────┤  │
│  │                                                          │  │
│  │  Process 1: Zitadel         Process 2: OAuth2-Proxy     │  │
│  │  Listening on :8080         Listening on :4180          │  │
│  │                                                          │  │
│  │  Process 3: Login UI                                    │  │
│  │  Listening on :3000                                     │  │
│  │                                                          │  │
│  │  Network Interface: 172.29.0.2                          │  │
│  │                                                          │  │
│  │  They all share localhost!                              │  │
│  │  localhost:8080 → Zitadel                               │  │
│  │  localhost:4180 → OAuth2-Proxy                          │  │
│  │  localhost:3000 → Login UI                              │  │
│  │                                                          │  │
│  └──────────────────────────────────────────────────────────┘  │
│       ↑                                                         │
│       │ Internal Docker network                                │
│       ↓                                                         │
│  ┌─────────────┐              ┌─────────────┐                  │
│  │ Papermerge  │              │ PostgreSQL  │                  │
│  │ (pm)        │              │ (db)        │                  │
│  │ :80         │              │ :5432       │                  │
│  │ 172.29.0.4  │              │ 172.29.0.5  │                  │
│  └─────────────┘              └─────────────┘                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
         ↑                      ↑                      ↑
         │                      │                      │
    Port 8081              Port 8080              Port 5432
    (OAuth2-Proxy)         (Zitadel)              (Database)
         │                      │                      │
         └──────────────────────┴──────────────────────┘
                          Host Machine
                        (Your Browser)
```

---

## Flow 1: Initial Login (First Time User Visits)

```
┌─────────────┐
│   Browser   │
│ (You)       │
└──────┬──────┘
       │
       │ 1. User navigates to Papermerge
       │    GET http://localhost:8081/
       │
       ↓
┌─────────────────────────────────┐
│    OAuth2-Proxy (:4180)         │ ← Port 8081 on host
│    Shared namespace with        │
│    Zitadel                      │
└──────┬──────────────────────────┘
       │
       │ 2. No auth cookie found!
       │    OAuth2-Proxy checks request
       │    Cookie: _oauth2_proxy=??? ❌ Not found
       │
       │ 3. Redirect to login
       │    HTTP 302 Redirect
       │    Location: http://localhost:8080/oauth/v2/authorize?
       │              client_id=353636209450343469@papermerge&
       │              redirect_uri=http://localhost:8081/oauth2/callback&
       │              response_type=code&
       │              scope=openid+profile+email&
       │              state=random-state-string&
       │              code_challenge=base64-challenge&
       │              code_challenge_method=S256
       │
       ↓
┌─────────────────────────────────┐
│   Browser follows redirect      │
└──────┬──────────────────────────┘
       │
       │ 4. Browser navigates to Zitadel
       │    GET http://localhost:8080/oauth/v2/authorize?...
       │
       ↓
┌─────────────────────────────────┐
│    Zitadel (:8080)              │ ← Port 8080 on host
│    Shared namespace with        │
│    OAuth2-Proxy                 │
└──────┬──────────────────────────┘
       │
       │ 5. User not logged in to Zitadel
       │    HTTP 302 Redirect
       │    Location: http://localhost:3000/ui/v2/login/login?authRequest=xyz
       │
       ↓
┌─────────────────────────────────┐
│   Zitadel Login UI (:3000)      │ ← Port 3000 on host
│   Shared namespace              │
└──────┬──────────────────────────┘
       │
       │ 6. Shows login form
       │    HTML form with username/password
       │
       ↓
┌─────────────────────────────────┐
│   Browser displays login page   │
└──────┬──────────────────────────┘
       │
       │ 7. User enters credentials
       │    POST http://localhost:3000/ui/v2/login/login
       │    username: root@my-organization.localhost
       │    password: AdminPassword123!
       │
       ↓
┌─────────────────────────────────┐
│   Zitadel Login UI (:3000)      │
└──────┬──────────────────────────┘
       │
       │ 8. Validates credentials with Zitadel API
       │    POST http://localhost:8080/v2/users/authenticate
       │
       ↓
┌─────────────────────────────────┐
│    Zitadel (:8080)              │
└──────┬──────────────────────────┘
       │
       │ 9. Checks credentials against database
       │    SELECT * FROM users WHERE username='root@...'
       │    Verifies password hash
       │
       ↓
┌─────────────────────────────────┐
│    PostgreSQL (db:5432)         │
└──────┬──────────────────────────┘
       │
       │ 10. Returns user data
       │     User found ✓
       │
       ↓
┌─────────────────────────────────┐
│    Zitadel (:8080)              │
└──────┬──────────────────────────┘
       │
       │ 11. Creates session, sets cookie
       │     Set-Cookie: zitadel.session=abc123...
       │     HTTP 302 Redirect back to authorize endpoint
       │     Location: http://localhost:8080/oauth/v2/authorize?authRequest=xyz
       │
       ↓
┌─────────────────────────────────┐
│   Browser (now authenticated)   │
└──────┬──────────────────────────┘
       │
       │ 12. Follows redirect with session cookie
       │     GET http://localhost:8080/oauth/v2/authorize?...
       │     Cookie: zitadel.session=abc123...
       │
       ↓
┌─────────────────────────────────┐
│    Zitadel (:8080)              │
└──────┬──────────────────────────┘
       │
       │ 13. User is authenticated!
       │     Generates authorization code
       │     HTTP 302 Redirect to OAuth2-Proxy callback
       │     Location: http://localhost:8081/oauth2/callback?
       │               code=authorization-code-xyz&
       │               state=random-state-string
       │
       ↓
┌─────────────────────────────────┐
│   Browser follows redirect      │
└──────┬──────────────────────────┘
       │
       │ 14. Browser goes to OAuth2-Proxy callback
       │     GET http://localhost:8081/oauth2/callback?code=xyz&state=...
       │
       ↓
┌─────────────────────────────────┐
│    OAuth2-Proxy (:4180)         │
└──────┬──────────────────────────┘
       │
       │ 15. Exchange authorization code for tokens
       │     POST http://localhost:8080/oauth/v2/token
       │     grant_type=authorization_code&
       │     code=authorization-code-xyz&
       │     redirect_uri=http://localhost:8081/oauth2/callback&
       │     code_verifier=original-random-string&
       │     client_id=353636209450343469@papermerge&
       │     client_secret=your-secret
       │
       ↓
┌─────────────────────────────────┐
│    Zitadel (:8080)              │
└──────┬──────────────────────────┘
       │
       │ 16. Validates code, returns tokens
       │     {
       │       "access_token": "Rko_puLc-UuqIISJ...",  ← Opaque token
       │       "id_token": "eyJhbG...",                 ← JWT token
       │       "refresh_token": "RT-xyz...",
       │       "token_type": "Bearer",
       │       "expires_in": 3600
       │     }
       │
       ↓
┌─────────────────────────────────┐
│    OAuth2-Proxy (:4180)         │
└──────┬──────────────────────────┘
       │
       │ 17. Decodes ID token to get user info
       │     ID Token (JWT) contains:
       │     {
       │       "sub": "355901215668240388",
       │       "email": "root@example.com",
       │       "preferred_username": "root@my-organization.localhost",
       │       "email_verified": true,
       │       ...
       │     }
       │
       │ 18. Creates encrypted session cookie
       │     Set-Cookie: _oauth2_proxy=encrypted-session-data
       │     (Contains: user ID, email, access token, refresh token)
       │
       │ 19. Redirects to original requested URL
       │     HTTP 302 Redirect
       │     Location: http://localhost:8081/
       │
       ↓
┌─────────────────────────────────┐
│   Browser (now has cookie)      │
└──────┬──────────────────────────┘
       │
       │ 20. Browser requests Papermerge again
       │     GET http://localhost:8081/
       │     Cookie: _oauth2_proxy=encrypted-session-data
       │
       ↓
       │
       │ Continue to Flow 2...
       ↓
```

---

## Flow 2: Authenticated Request to Papermerge

```
┌─────────────┐
│   Browser   │
│ (You)       │
└──────┬──────┘
       │
       │ GET http://localhost:8081/
       │ Cookie: _oauth2_proxy=encrypted-session-data
       │
       ↓
┌─────────────────────────────────────────────────┐
│    OAuth2-Proxy (:4180)                         │
└──────┬──────────────────────────────────────────┘
       │
       │ 1. Decrypt and validate session cookie
       │    ✓ Cookie is valid
       │    ✓ Not expired
       │    ✓ Signature matches
       │
       │ 2. Extract user info from session:
       │    user_id: 355901215668240388
       │    email: root@my-organization.localhost
       │    access_token: Rko_puLc-UuqIISJ...
       │
       │ 3. Forward request to Papermerge with headers
       │    GET http://pm:80/
       │    Host: localhost:8081
       │    X-Forwarded-User: 355901215668240388
       │    X-Forwarded-Email: 355901215668240388
       │    X-Forwarded-Preferred-Username: root@my-organization.localhost
       │    X-Forwarded-Access-Token: Rko_puLc-UuqIISJ...
       │    X-Forwarded-Groups: (roles if configured)
       │    Cookie: _oauth2_proxy=... (original cookie)
       │
       ↓
┌─────────────────────────────────────────────────┐
│    Papermerge (pm:80)                           │
│    IP: 172.29.0.4                               │
└──────┬──────────────────────────────────────────┘
       │
       │ 4. Papermerge receives request
       │    Request headers available:
       │    - X-Forwarded-User: 355901215668240388
       │    - X-Forwarded-Email: 355901215668240388
       │    - X-Forwarded-Preferred-Username: root@...
       │    - Authorization: Bearer Rko_puLc-UuqIISJ... (if enabled)
       │
       │ 5. Authentication middleware runs
       │    Code: papermerge.core.features.auth.__init__.py
       │    Function: get_current_user()
       │
       │ 6. Try JWT authentication first (if token present)
       │    ❌ Token is opaque, not JWT (no dots)
       │    Log: "Token doesn't contain dots"
       │
       │ 7. Fall back to Remote-User authentication
       │    ✓ X-Forwarded-User header found
       │    user_id = "355901215668240388"
       │
       │ 8. Check if user exists in database
       │    SELECT * FROM core_user 
       │    WHERE username = '355901215668240388'
       │
       ↓
┌─────────────────────────────────────────────────┐
│    PostgreSQL (db:5432)                         │
│    Database: pmdb                               │
└──────┬──────────────────────────────────────────┘
       │
       │ 9. User not found! (First time login)
       │    Returns: NoResultFound exception
       │
       ↓
┌─────────────────────────────────────────────────┐
│    Papermerge (pm:80)                           │
└──────┬──────────────────────────────────────────┘
       │
       │ 10. Create new user automatically
       │     INSERT INTO core_user (
       │       id, username, email, password,
       │       is_superuser, is_active
       │     ) VALUES (
       │       gen_random_uuid(),
       │       '355901215668240388',
       │       '355901215668240388',
       │       '-',  -- No password (SSO only)
       │       false, -- Not superuser by default
       │       true
       │     )
       │
       ↓
┌─────────────────────────────────────────────────┐
│    PostgreSQL (db:5432)                         │
└──────┬──────────────────────────────────────────┘
       │
       │ 11. User created
       │     id: 3ef3cb6f-f180-4c29-80fa-b7aceff64ed7
       │     username: 355901215668240388
       │
       ↓
┌─────────────────────────────────────────────────┐
│    Papermerge (pm:80)                           │
└──────┬──────────────────────────────────────────┘
       │
       │ 12. Load user permissions/roles
       │     Check user.is_superuser → false
       │     Load roles from user.roles → []
       │     Build scopes list
       │
       │ 13. Authentication complete!
       │     User object created with:
       │     - id: 3ef3cb6f-f180-4c29-80fa-b7aceff64ed7
       │     - username: 355901215668240388
       │     - scopes: [basic permissions]
       │
       │ 14. Process the request
       │     Route: GET /
       │     Serve Papermerge UI (HTML/JS/CSS)
       │
       │ 15. Return response
       │     HTTP 200 OK
       │     Content-Type: text/html
       │     <html>...</html>
       │
       ↓
┌─────────────────────────────────────────────────┐
│    OAuth2-Proxy (:4180)                         │
└──────┬──────────────────────────────────────────┘
       │
       │ 16. Proxy returns response to browser
       │     HTTP 200 OK
       │     (Transparently passes through)
       │
       ↓
┌─────────────────────────────────────────────────┐
│    Browser displays Papermerge UI               │
└─────────────────────────────────────────────────┘
```

---

## Flow 3: Subsequent API Requests

```
┌─────────────┐
│   Browser   │
│  (Logged in)│
└──────┬──────┘
       │
       │ GET http://localhost:8081/api/users/me
       │ Cookie: _oauth2_proxy=encrypted-session-data
       │
       ↓
┌─────────────────────────────────────────────────┐
│    OAuth2-Proxy (:4180)                         │
└──────┬──────────────────────────────────────────┘
       │
       │ 1. Validate cookie (same as before)
       │ 2. Add headers
       │ 3. Forward to Papermerge
       │
       │    GET http://pm:80/api/users/me
       │    X-Forwarded-User: 355901215668240388
       │    X-Forwarded-Email: 355901215668240388
       │    ...
       │
       ↓
┌─────────────────────────────────────────────────┐
│    Papermerge (pm:80)                           │
└──────┬──────────────────────────────────────────┘
       │
       │ 4. Authenticate (same process)
       │ 5. User exists this time! (from database)
       │ 6. Return user data as JSON
       │
       │    HTTP 200 OK
       │    {
       │      "id": "3ef3cb6f-f180-4c29-80fa-b7aceff64ed7",
       │      "username": "355901215668240388",
       │      "email": "355901215668240388",
       │      "is_superuser": false,
       │      ...
       │    }
       │
       ↓
┌─────────────────────────────────────────────────┐
│    OAuth2-Proxy (passes through)                │
└──────┬──────────────────────────────────────────┘
       │
       ↓
┌─────────────────────────────────────────────────┐
│    Browser receives JSON                        │
│    JavaScript updates UI                        │
└─────────────────────────────────────────────────┘
```

---

## Flow 4: Token Refresh (After 55 Minutes)

```
┌─────────────┐
│   Browser   │
└──────┬──────┘
       │
       │ GET http://localhost:8081/some-page
       │ Cookie: _oauth2_proxy=encrypted-session-data
       │
       ↓
┌─────────────────────────────────────────────────┐
│    OAuth2-Proxy (:4180)                         │
└──────┬──────────────────────────────────────────┘
       │
       │ 1. Check session cookie
       │    ✓ Cookie valid
       │    ✓ User authenticated
       │    ⚠️  Access token expired! (> 55 min old)
       │
       │ 2. Use refresh token to get new access token
       │    POST http://localhost:8080/oauth/v2/token
       │    grant_type=refresh_token&
       │    refresh_token=RT-xyz...&
       │    client_id=353636209450343469@papermerge&
       │    client_secret=your-secret
       │
       ↓
┌─────────────────────────────────────────────────┐
│    Zitadel (:8080)                              │
└──────┬──────────────────────────────────────────┘
       │
       │ 3. Validate refresh token
       │    Check database for refresh token
       │    ✓ Token is valid
       │    ✓ Not expired
       │    ✓ Not revoked
       │
       │ 4. Issue new tokens
       │    {
       │      "access_token": "NEW-Rko_puLc...",
       │      "id_token": "NEW-eyJhbG...",
       │      "refresh_token": "NEW-RT-xyz...",  ← May be rotated
       │      "expires_in": 3600
       │    }
       │
       ↓
┌─────────────────────────────────────────────────┐
│    OAuth2-Proxy (:4180)                         │
└──────┬──────────────────────────────────────────┘
       │
       │ 5. Update session with new tokens
       │    Set-Cookie: _oauth2_proxy=NEW-encrypted-session
       │
       │ 6. Continue processing request normally
       │    Forward to Papermerge with updated headers
       │
       ↓
       │
       │ User never notices! Seamless refresh.
       ↓
```

---

## Flow 5: Logout

```
┌─────────────┐
│   Browser   │
└──────┬──────┘
       │
       │ User clicks "Logout" in Papermerge
       │ GET http://localhost:8081/logout
       │
       ↓
┌─────────────────────────────────────────────────┐
│    OAuth2-Proxy (:4180)                         │
└──────┬──────────────────────────────────────────┘
       │
       │ 1. Delete OAuth2-Proxy session cookie
       │    Set-Cookie: _oauth2_proxy=; Max-Age=0
       │
       │ 2. Redirect to Zitadel logout
       │    HTTP 302 Redirect
       │    Location: http://localhost:8080/oidc/v1/end_session?
       │              id_token_hint=eyJhbG...&
       │              post_logout_redirect_uri=http://localhost:8081
       │
       ↓
┌─────────────────────────────────────────────────┐
│    Zitadel (:8080)                              │
└──────┬──────────────────────────────────────────┘
       │
       │ 3. End Zitadel session
       │    Delete zitadel.session cookie
       │    Invalidate tokens in database
       │
       │ 4. Redirect back to application
       │    HTTP 302 Redirect
       │    Location: http://localhost:8081
       │
       ↓
┌─────────────────────────────────────────────────┐
│    Browser (logged out)                         │
│    Next request will trigger login flow again   │
└─────────────────────────────────────────────────┘
```

---

## Key Observations

### 1. **Network Namespace Sharing**
```
Zitadel, OAuth2-Proxy, and Login UI all run in the SAME network namespace.
This means:
- They share the same localhost
- OAuth2-Proxy can reach Zitadel via localhost:8080
- Login UI can reach Zitadel via localhost:8080
- They share the same external ports via the zitadel container
```

### 2. **Port Mappings**
```
Host Machine          →  Docker Network
localhost:8080        →  zitadel container :8080  (Zitadel API)
localhost:3000        →  zitadel container :3000  (Login UI)
localhost:8081        →  zitadel container :4180  (OAuth2-Proxy)
localhost:5432        →  db container :5432       (PostgreSQL)
```

### 3. **Authentication Flow Summary**
```
Browser → OAuth2-Proxy → Checks cookie
                       ↓ (no cookie)
                       Redirect to Zitadel
                       ↓
                    Zitadel → Login UI → User enters credentials
                       ↓
                    Validate & create session
                       ↓
                    Return to OAuth2-Proxy with code
                       ↓
OAuth2-Proxy → Exchange code for tokens
            → Create session cookie
            → Forward to Papermerge with headers
                       ↓
Papermerge  → Read X-Forwarded-User header
            → Create/fetch user from database
            → Return response
```

### 4. **Headers Flow**
```
OAuth2-Proxy extracts from ID token:
  sub → X-Forwarded-User
  email → X-Forwarded-Email  
  preferred_username → X-Forwarded-Preferred-Username
  roles (if configured) → X-Forwarded-Groups

Papermerge reads headers:
  PM_REMOTE_USER_HEADER=X-Forwarded-User
  PM_REMOTE_EMAIL_HEADER=X-Forwarded-Email
  PM_REMOTE_GROUPS_HEADER=X-Forwarded-Groups
  PM_REMOTE_ROLES_HEADER=X-Forwarded-Roles
```

### 5. **Database Interactions**
```
Zitadel Database (zitadel):
  - User credentials
  - OIDC clients/applications
  - Tokens (access, refresh, authorization codes)
  - Sessions

Papermerge Database (pmdb):
  - User profiles (created from SSO)
  - Documents
  - Permissions
  - Document types/custom fields
```

---

## Security Note

```
┌─────────────────────────────────────────────────┐
│  Security Boundary                              │
├─────────────────────────────────────────────────┤
│                                                 │
│  OAuth2-Proxy validates ALL authentication     │
│  before forwarding to Papermerge.               │
│                                                 │
│  Papermerge trusts the X-Forwarded-* headers    │
│  because it's behind OAuth2-Proxy.              │
│                                                 │
│  NEVER expose Papermerge directly to internet!  │
│  Always go through OAuth2-Proxy.                │
│                                                 │
└─────────────────────────────────────────────────┘
```