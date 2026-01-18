# Papermerge + Zitadel Automated Setup

This setup provides **fully automated provisioning** of Papermerge with Zitadel authentication. No manual configuration required!

## Quick Start

### Prerequisites
- Docker and Docker Compose
- `openssl` (for generating secrets)
- `jq` (for JSON parsing - will be installed automatically in provisioner)

### One-Command Setup

```bash
chmod +x start.sh provision-zitadel.sh
./start.sh
```

That's it! The script will:
1. Generate a secure OAuth2 cookie secret
2. Start all containers
3. Wait for Zitadel to initialize
4. Automatically create a Zitadel project and application
5. Extract the client ID and secret
6. Update your `.env` file
7. Restart the OAuth2-Proxy with credentials

## What Happens Behind the Scenes

### 1. Initial Startup
The `docker-compose.yaml` includes a `provisioner` service that:
- Waits for Zitadel to be healthy
- Uses Zitadel's admin PAT (Personal Access Token) to access the API
- Creates a project named "Papermerge"
- Creates an OAuth2 application with proper redirect URIs
- Saves credentials to `zitadel-credentials.env`

### 2. Credential Flow
```
Docker Compose Up
    ↓
Zitadel starts → Generates admin.pat
    ↓
Provisioner reads admin.pat
    ↓
Provisioner calls Zitadel API:
  - POST /management/v1/projects (create project)
  - POST /management/v1/projects/{id}/apps/oidc (create app)
    ↓
Provisioner saves credentials → zitadel-credentials.env
    ↓
start.sh reads credentials → Updates .env
    ↓
OAuth2-Proxy restarts with credentials
```

### 3. File Structure
```
.
├── docker-compose-automated.yaml  # Main compose file
├── provision-zitadel.sh          # Provisioning script
├── start.sh                       # Startup orchestrator
├── init.sql                       # Database initialization
├── .env                          # Auto-generated credentials
└── zitadel-credentials.env       # Provisioner output
```

## Manual Setup (Alternative)

If you prefer manual control:

```bash
# 1. Generate cookie secret
openssl rand -base64 32 | head -c 32

# 2. Create .env file
cat > .env << EOF
OAUTH2_COOKIE_SECRET=your-generated-secret
ZITADEL_CLIENT_ID=
ZITADEL_CLIENT_SECRET=
EOF

# 3. Start containers
docker compose up -d

# 4. Wait for provisioner
docker compose logs -f provisioner

# 5. Update .env with credentials from zitadel-credentials.env
# 6. Restart proxy
docker compose restart proxy
```

## First Login

After setup completes:

1. **Access Papermerge**: http://localhost:8081/
2. **Login with**:
   - Username: `root@my-organization.localhost`
   - Password: `AdminPassword123!`

3. **Grant Superuser Status** (first time only):
   ```bash
   docker compose exec db psql -U postgres -d pmdb
   ```

   In psql:
   ```sql
   -- Find your user (will be a long numeric ID)
   SELECT id, username, is_superuser FROM users WHERE username != 'system';

   -- Make them superuser
   UPDATE users SET is_superuser = true WHERE username = 'YOUR_USERNAME_FROM_ABOVE';
   ```

## Troubleshooting

### Provisioner Fails

Check logs:
```bash
docker compose logs provisioner
```

Common issues:
- **Zitadel not ready**: Provisioner waits for Zitadel's `/debug/ready` endpoint
- **Missing admin.pat**: Ensure the machine user env vars are set in docker-compose
- **API errors**: Check Zitadel logs: `docker compose logs zitadel`

### OAuth2-Proxy Can't Connect

If you see authentication errors:
```bash
# Check proxy logs
docker compose logs proxy

# Verify credentials are in .env
cat .env

# Manually restart
docker compose restart proxy
```

### Re-provisioning

If you need to start fresh:

```bash
# Stop and remove volumes
docker compose down -v

# Remove generated files
rm -f .env zitadel-credentials.env admin.pat login-client.pat

# Start again
./start.sh
```

## Architecture

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
│  │  Process 3: Login UI        Process 4: Provisioner      │  │
│  │  Listening on :3000         (runs once, exits)          │  │
│  │                                                          │  │
│  └──────────────────────────────────────────────────────────┘  │
│       ↑                                                         │
│       │                                                         │
│  ┌─────────────┐              ┌─────────────┐                  │
│  │ Papermerge  │              │ PostgreSQL  │                  │
│  │ (pm)        │              │ (db)        │                  │
│  │ :80         │              │ :5432       │                  │
│  └─────────────┘              └─────────────┘                  │
└─────────────────────────────────────────────────────────────────┘
```

## API Endpoints Used

The provisioner uses these Zitadel Management API endpoints:

- `POST /management/v1/orgs/_search` - Find organization
- `POST /management/v1/projects/_search` - Check existing project
- `POST /management/v1/projects` - Create project
- `POST /management/v1/projects/{id}/apps/_search` - Check existing app
- `POST /management/v1/projects/{id}/apps/oidc` - Create OIDC application

## Environment Variables

### Auto-Generated
- `OAUTH2_COOKIE_SECRET` - Random 32-char secret for cookie encryption
- `ZITADEL_CLIENT_ID` - OAuth2 client ID (extracted from API)
- `ZITADEL_CLIENT_SECRET` - OAuth2 client secret (only available on first creation!)

### Zitadel Configuration
These are set in docker-compose and enable automated provisioning:
- `ZITADEL_FIRSTINSTANCE_PATPATH` - Where to write admin PAT
- `ZITADEL_FIRSTINSTANCE_ORG_MACHINE_MACHINE_USERNAME` - Machine user name
- `ZITADEL_FIRSTINSTANCE_ORG_MACHINE_PAT_EXPIRATIONDATE` - PAT expiry

## Security Notes

⚠️ **This is a development/demo setup!**

For production:
1. Use proper HTTPS/TLS
2. Change default passwords
3. Use secure cookie settings
4. Restrict email domains in OAuth2-Proxy
5. Use proper secrets management (not .env files)
6. Enable CSRF protection
7. Review and restrict API permissions

## Advanced: Re-running Provisioner

If you need to re-run just the provisioner:

```bash
docker compose run --rm provisioner
```

The provisioner is idempotent - it will detect existing projects/apps and skip creation.

## Customization

### Different Redirect URLs

Edit `provision-zitadel.sh`:
```json
"redirectUris": [
    "http://localhost:8081/oauth2/callback",
    "https://your-domain.com/oauth2/callback"
],
```

### Additional Scopes

Edit docker-compose proxy service:
```yaml
- --scope=openid profile email roles groups
```

### Different Organization Name

Edit docker-compose zitadel service:
```yaml
ZITADEL_FIRSTINSTANCE_ORG_NAME: Your Company
```

## License

This setup is for demonstration purposes. Papermerge and Zitadel are separate projects with their own licenses.
