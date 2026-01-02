# Papermerge with Zitadel Cloud OIDC Authentication

This directory contains Docker configuration for running Papermerge with Zitadel Cloud
as the OIDC identity provider.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  Browser                                                        │
│     │                                                           │
│     ▼                                                           │
│  ┌──────────────────┐                                           │
│  │  OAuth2-Proxy    │◄────────────┐                             │
│  │  (Port 8080)     │             │ OIDC Auth                   │
│  └────────┬─────────┘             │                             │
│           │                       │                             │
│           │ Authorization         │                             │
│           │ Header (JWT)          │                             │
│           ▼                       │                             │
│  ┌──────────────────┐    ┌───────┴────────┐                     │
│  │   Papermerge     │    │ Zitadel Cloud  │                     │
│  │   (Port 80)      │    │ (pm36dev)      │                     │
│  └────────┬─────────┘    └────────────────┘                     │
│           │                                                     │
│           ▼                                                     │
│  ┌───────────────────────────────────────────┐                  │
│  │           PostgreSQL 17 (Port 5432)       │                  │
│  └───────────────────────────────────────────┘                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

### 1. Configure Zitadel Cloud Application

1. Log in to your Zitadel Cloud console (pm36dev instance)
2. Create a new Project (if you don't have one already)
3. Create a new Application:
   - **Name**: Papermerge
   - **Type**: Web
   - **Authentication Method**: `CODE` (Authorization Code with PKCE) or `POST` (Client Secret POST)

4. Configure the application:
   - **Redirect URIs**: `http://localhost:8080/oauth2/callback`
   - **Post Logout Redirect URIs**: `http://localhost:8080`
   - Enable the following scopes: `openid`, `profile`, `email`

5. Note down:
   - **Client ID**: Something like `123456789012345678@projectname`
   - **Client Secret**: Generated secret (only for Confidential clients)
   - **Issuer URL**: Your instance URL, e.g., `https://pm36dev-abc123.zitadel.cloud`

### 2. Create a Test User

1. In Zitadel Console, go to **Users**
2. Click **New** to create a user
3. Fill in:
   - Username
   - Email
   - Password
4. The user will be able to log in to Papermerge

## Quick Start

### 1. Generate Cookie Secret

```bash
export OAUTH2_COOKIE_SECRET=$(openssl rand -base64 32)
echo "OAUTH2_COOKIE_SECRET=$OAUTH2_COOKIE_SECRET"
```

### 2. Create Environment File

```bash
cp .env.example .env
```

Edit `.env` with your Zitadel configuration:

```bash
# Your actual values
ZITADEL_DOMAIN=pm36dev-abc123.zitadel.cloud
ZITADEL_ISSUER_URL=https://pm36dev-abc123.zitadel.cloud
ZITADEL_CLIENT_ID=123456789012345678@papermerge
ZITADEL_CLIENT_SECRET=your_client_secret_here
OAUTH2_COOKIE_SECRET=your_generated_secret_here
```

### 3. Start Services

```bash
docker compose up -d
```

Or with logs:

```bash
docker compose up 2>&1 | tee compose.log
```

### 4. Access Papermerge

Open http://localhost:8080 in your browser. You will be redirected to Zitadel for authentication.

## Troubleshooting

### Check Service Status

```bash
docker compose ps
docker compose logs -f
```

### Common Issues

#### 1. "Invalid redirect URI" error

Make sure you've added `http://localhost:8080/oauth2/callback` to the Redirect URIs in your Zitadel application.

#### 2. "Invalid client" error

- Verify `ZITADEL_CLIENT_ID` matches exactly what's shown in Zitadel Console
- Verify `ZITADEL_CLIENT_SECRET` is correct
- Check that your application type supports client secrets

#### 3. "Discovery failed" error

- Verify `ZITADEL_ISSUER_URL` is correct (no trailing slash)
- Test the discovery endpoint: `curl https://your-instance.zitadel.cloud/.well-known/openid-configuration`

#### 4. User not created in Papermerge

Check the Papermerge logs for authentication details:

```bash
docker compose logs papermerge | grep -i auth
```

### Verify Zitadel OIDC Configuration

Test your Zitadel instance's OIDC discovery:

```bash
curl https://your-instance.zitadel.cloud/.well-known/openid-configuration | jq
```

This should return endpoints including:
- `authorization_endpoint`
- `token_endpoint`
- `end_session_endpoint`
- `jwks_uri`

## Configuration Reference

### Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `ZITADEL_DOMAIN` | Zitadel instance domain (no https) | `pm36dev-abc123.zitadel.cloud` |
| `ZITADEL_ISSUER_URL` | Full issuer URL | `https://pm36dev-abc123.zitadel.cloud` |
| `ZITADEL_CLIENT_ID` | Application Client ID | `123456789@project` |
| `ZITADEL_CLIENT_SECRET` | Application Client Secret | (generated) |
| `OAUTH2_COOKIE_SECRET` | Cookie encryption secret | (generate with openssl) |

### Papermerge Environment Variables

| Variable | Description |
|----------|-------------|
| `PM_OIDC_LOGOUT_URL` | Zitadel's end_session endpoint |
| `PM_POST_LOGOUT_REDIRECT_URI` | Where to redirect after logout |
| `PM_OIDC_CLIENT_ID` | Client ID for logout flow |

## Zitadel Application Settings

### Recommended Settings for Web Application

- **Application Type**: Web
- **Authentication Method**: Choose based on your security requirements:
  - `POST` - Client Secret sent in POST body (simpler)
  - `PKCE` - No client secret needed, more secure for public clients
- **Grant Types**: `AUTHORIZATION_CODE`, `REFRESH_TOKEN`
- **Response Types**: `CODE`

### Required Redirect URIs

- **Redirect URI**: `http://localhost:8080/oauth2/callback`
- **Post Logout Redirect URI**: `http://localhost:8080`

### Dev Mode

If using HTTP (localhost), enable **Dev Mode** in the application settings.

## How Authentication Works

1. User accesses Papermerge at `http://localhost:8080`
2. OAuth2-Proxy intercepts and checks for valid session
3. If no session, redirects to Zitadel login page
4. User authenticates with Zitadel
5. Zitadel redirects back to OAuth2-Proxy with authorization code
6. OAuth2-Proxy exchanges code for tokens
7. OAuth2-Proxy creates session and forwards requests to Papermerge with JWT in Authorization header
8. Papermerge validates JWT and creates/updates user
9. Users are auto-created on first login based on JWT claims

## Logout Flow

1. User clicks logout in Papermerge
2. Papermerge redirects to OAuth2-Proxy's `/oauth2/sign_out`
3. OAuth2-Proxy clears its session and redirects to Zitadel's `end_session` endpoint
4. Zitadel terminates the SSO session
5. User is redirected back to Papermerge login page
