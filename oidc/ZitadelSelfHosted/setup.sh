#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                                                                ║"
echo "║   Papermerge + Self-Hosted Zitadel Setup Script               ║"
echo "║                                                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Function to generate random base64 string
generate_secret() {
    openssl rand -base64 32 | tr -d '\n'
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"

if ! command_exists docker; then
    echo -e "${RED}Error: Docker is not installed${NC}"
    exit 1
fi

if ! command_exists openssl; then
    echo -e "${RED}Error: OpenSSL is not installed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All prerequisites met${NC}\n"

# Check if .env already exists
if [ -f "$SCRIPT_DIR/.env" ]; then
    echo -e "${YELLOW}Warning: .env file already exists${NC}"
    read -p "Do you want to overwrite it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${BLUE}Using existing .env file${NC}"
        USE_EXISTING_ENV=true
    else
        USE_EXISTING_ENV=false
    fi
else
    USE_EXISTING_ENV=false
fi

# Generate .env file if needed
if [ "$USE_EXISTING_ENV" = false ]; then
    echo -e "${YELLOW}Generating .env file with secure secrets...${NC}"

    # Generate secrets
    ZITADEL_MASTERKEY=$(generate_secret)
    OAUTH2_COOKIE_SECRET=$(generate_secret)
    POSTGRES_PASSWORD=$(generate_secret | cut -c1-16)

    # Prompt for admin password
    echo -e "${BLUE}Setting up Zitadel admin account${NC}"
    read -p "Enter admin username (default: admin): " ADMIN_USERNAME
    ADMIN_USERNAME=${ADMIN_USERNAME:-admin}

    while true; do
        read -s -p "Enter admin password (min 8 chars, must include: uppercase, lowercase, number, symbol): " ADMIN_PASSWORD
        echo
        read -s -p "Confirm admin password: " ADMIN_PASSWORD_CONFIRM
        echo

        if [ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]; then
            echo -e "${RED}Passwords do not match. Please try again.${NC}"
            continue
        fi

        # Basic password validation
        if [ ${#ADMIN_PASSWORD} -lt 8 ]; then
            echo -e "${RED}Password must be at least 8 characters. Please try again.${NC}"
            continue
        fi

        break
    done

    # Create .env file
    cat > "$SCRIPT_DIR/.env" <<EOF
# ==============================================================================
# Zitadel Self-Hosted Configuration
# Generated on: $(date)
# ==============================================================================

# Zitadel Master Key (REQUIRED - DO NOT SHARE)
ZITADEL_MASTERKEY=$ZITADEL_MASTERKEY

# Zitadel External Domain Configuration
ZITADEL_EXTERNAL_DOMAIN=localhost
ZITADEL_EXTERNAL_PORT=8081
ZITADEL_EXTERNAL_SECURE=false
ZITADEL_TLS_ENABLED=false

# Zitadel Organization and Admin User
ZITADEL_ORG_NAME=Papermerge
ZITADEL_ADMIN_USERNAME=$ADMIN_USERNAME
ZITADEL_ADMIN_PASSWORD=$ADMIN_PASSWORD
ZITADEL_ADMIN_PASSWORD_CHANGE_REQUIRED=true

# Zitadel Logging
ZITADEL_LOG_LEVEL=info
ZITADEL_LOG_FORMAT=text

# ==============================================================================
# Zitadel OIDC Application Configuration
# ==============================================================================
# IMPORTANT: After first startup, configure these in Zitadel Console:
# 1. Go to http://localhost:8081 and login with admin credentials above
# 2. Create Project: "Papermerge DMS"
# 3. Create Application: Type=Web, Auth=PKCE
# 4. Add Redirect URI: http://localhost:8080/oauth2/callback
# 5. Copy Client ID and Client Secret below

ZITADEL_CLIENT_ID=
ZITADEL_CLIENT_SECRET=

# ==============================================================================
# SMTP Configuration (using Mailpit for development)
# ==============================================================================
SMTP_HOST=mailpit
SMTP_PORT=1025
SMTP_USER=
SMTP_PASSWORD=
SMTP_TLS=false
SMTP_FROM=noreply@papermerge.local
SMTP_FROM_NAME=Papermerge DMS
SMTP_REPLY_TO=

# ==============================================================================
# OAuth2 Proxy Configuration
# ==============================================================================
OAUTH2_COOKIE_SECRET=$OAUTH2_COOKIE_SECRET

# ==============================================================================
# PostgreSQL Configuration (Shared for Zitadel and Papermerge)
# ==============================================================================
# PostgreSQL hosts both Zitadel and Papermerge databases
POSTGRES_USER=postgres
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# Database names (created automatically via init-dbs.sql)
ZITADEL_DB_NAME=zitadel
PAPERMERGE_DB_NAME=papermerge
EOF

    chmod 600 "$SCRIPT_DIR/.env"
    echo -e "${GREEN}✓ .env file created successfully${NC}\n"
else
    echo -e "${BLUE}Using existing configuration${NC}\n"
fi

# Display configuration summary
echo -e "${BLUE}Configuration Summary:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
source "$SCRIPT_DIR/.env"
echo -e "Zitadel Admin: ${GREEN}$ZITADEL_ADMIN_USERNAME${NC}"
echo -e "PostgreSQL User: ${GREEN}$POSTGRES_USER${NC}"
echo -e "Zitadel DB: ${GREEN}$ZITADEL_DB_NAME${NC}"
echo -e "Papermerge DB: ${GREEN}$PAPERMERGE_DB_NAME${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo

# Check if Client ID is configured
if [ -z "$ZITADEL_CLIENT_ID" ]; then
    echo -e "${YELLOW}⚠ ZITADEL_CLIENT_ID is not set${NC}"
    echo -e "${YELLOW}⚠ You'll need to configure this after Zitadel starts${NC}\n"
fi

# Ask if user wants to start services
echo -e "${BLUE}Ready to start services${NC}"
read -p "Start Docker Compose now? (Y/n): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo -e "${YELLOW}Starting services with Docker Compose...${NC}"
    # Start services
    docker compose -f "$SCRIPT_DIR/docker-compose-zitadel-selfhosted.yml" up -d

    echo -e "\n${GREEN}✓ Services started successfully${NC}\n"
    
    # Wait for services to be healthy
    echo -e "${YELLOW}Waiting for services to be ready (this may take 60-90 seconds)...${NC}"
    sleep 10
    
    # Check service status
    echo -e "\n${BLUE}Service Status:${NC}"
    docker compose -f "$SCRIPT_DIR/docker-compose-zitadel-selfhosted.yml" ps
    
    echo -e "\n${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                                ║${NC}"
    echo -e "${GREEN}║                  Services Started Successfully!                ║${NC}"
    echo -e "${GREEN}║                                                                ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    
    echo -e "\n${BLUE}Access URLs:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "Zitadel Console:  ${GREEN}http://localhost:8081${NC}"
    echo -e "Papermerge:       ${GREEN}http://localhost:8080${NC}"
    echo -e "Mailpit (emails): ${GREEN}http://localhost:8025${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    echo -e "\n${YELLOW}Next Steps:${NC}"
    echo "1. Wait 60-90 seconds for Zitadel to fully initialize"
    echo "2. Access Zitadel Console: http://localhost:8081"
    echo "3. Login with admin credentials:"
    echo -e "   Username: ${GREEN}$ZITADEL_ADMIN_USERNAME${NC}"
    echo "   Password: (the password you just set)"
    echo "4. Follow SETUP_GUIDE.md to configure:"
    echo "   • Create Project and Application"
    echo "   • Create 'privateUser' role"
    echo "   • Enable user registration"
    echo "   • Configure automatic role assignment"
    echo "5. Update .env with Client ID and Secret"
    echo "6. Restart services: docker compose -f docker-compose-zitadel-selfhosted.yml restart"
    
    echo -e "\n${BLUE}Useful Commands:${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "View logs:     docker compose -f docker-compose-zitadel-selfhosted.yml logs -f"
    echo "Stop services: docker compose -f docker-compose-zitadel-selfhosted.yml down"
    echo "Restart:       docker compose -f docker-compose-zitadel-selfhosted.yml restart"
    echo "Check status:  docker compose -f docker-compose-zitadel-selfhosted.yml ps"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    echo -e "\n${GREEN}Setup complete! 🎉${NC}"
    echo -e "${YELLOW}Please review SETUP_GUIDE.md for detailed configuration instructions.${NC}\n"
else
    echo -e "${BLUE}Services not started. To start manually, run:${NC}"
    echo "docker compose -f docker-compose-zitadel-selfhosted.yml up -d"
fi

# Save admin credentials reminder
if [ "$USE_EXISTING_ENV" = false ]; then
    cat > "$SCRIPT_DIR/ADMIN_CREDENTIALS.txt" <<EOF
Zitadel Admin Credentials
Generated on: $(date)

Console URL: http://localhost:8081
Username: $ZITADEL_ADMIN_USERNAME
Password: [The password you entered during setup]

IMPORTANT: 
- Keep this file secure or delete it after saving credentials elsewhere
- You'll be prompted to change the password on first login
- This file is NOT tracked in git (added to .gitignore)
EOF
    
    chmod 600 "$SCRIPT_DIR/ADMIN_CREDENTIALS.txt"
    echo -e "${GREEN}Admin credentials saved to: ADMIN_CREDENTIALS.txt${NC}"
    echo -e "${YELLOW}Remember to keep this file secure!${NC}\n"
fi
