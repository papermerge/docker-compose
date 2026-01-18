#!/bin/bash
set -e

echo "======================================================"
echo "Papermerge + Zitadel Automated Setup"
echo "======================================================"
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo "Creating .env file from template..."

    # Generate a secure cookie secret
    COOKIE_SECRET=$(openssl rand -base64 32 | head -c 32)

    cat > .env << EOF
# Generated OAuth2 Cookie Secret
OAUTH2_COOKIE_SECRET=${COOKIE_SECRET}

# These will be auto-populated after provisioning
ZITADEL_CLIENT_ID=
ZITADEL_CLIENT_SECRET=
EOF

    echo ".env file created with cookie secret"
else
    echo ".env file already exists"
fi

echo ""
echo "Starting containers (this may take a minute)..."
docker compose up -d

echo ""
echo "Waiting for provisioning to complete..."
# Wait for the provisioner container to finish
while docker compose ps provisioner | grep -q "running"; do
    echo "  Provisioning in progress..."
    sleep 2
done

# Check if provisioning was successful
if [ -f zitadel-credentials.env ]; then
    echo ""
    echo "✓ Provisioning completed successfully!"
    echo ""

    # Read the generated credentials
    source zitadel-credentials.env

    # Check if we got both credentials
    if [ -n "$ZITADEL_CLIENT_ID" ] && [ -n "$ZITADEL_CLIENT_SECRET" ]; then
        echo "Updating .env with Zitadel credentials..."

        # Update .env file with new credentials
        # Preserve the cookie secret, update the client credentials
        COOKIE_SECRET=$(grep OAUTH2_COOKIE_SECRET .env | cut -d '=' -f2)

        cat > .env << EOF
# OAuth2 Cookie Secret
OAUTH2_COOKIE_SECRET=${COOKIE_SECRET}

# Auto-generated Zitadel credentials
ZITADEL_CLIENT_ID=${ZITADEL_CLIENT_ID}
ZITADEL_CLIENT_SECRET=${ZITADEL_CLIENT_SECRET}
EOF

        echo "✓ Credentials added to .env"
        echo ""
        echo "Restarting OAuth2-Proxy with new credentials..."
        docker compose -f docker-compose.yaml restart proxy

        echo ""
        echo "======================================================"
        echo "Setup Complete! 🎉"
        echo "======================================================"
        echo ""
        echo "Papermerge is now accessible at: http://localhost:8081/"
        echo "Zitadel console at: http://localhost:8080/ui/console"
        echo ""
        echo "Login credentials:"
        echo "  Username: root@my-organization.localhost"
        echo "  Password: AdminPassword123!"
        echo ""
        echo "⚠️  IMPORTANT: On first login to Papermerge, you need to"
        echo "    make your user a superuser. Run this command:"
        echo ""
        echo "    docker compose -f docker-compose.yaml exec db psql -U postgres -d pmdb"
        echo ""
        echo "    Then in psql:"
        echo "    SELECT id, username FROM users WHERE username != 'system';"
        echo "    UPDATE users SET is_superuser = true WHERE username = '<your-username>';"
        echo ""
        echo "======================================================"
    else
        echo "⚠️  WARNING: Application already exists"
        echo ""
        echo "The Zitadel application was already created in a previous run."
        echo "You need to manually update .env with the existing client secret."
        echo ""
        echo "Your client ID: ${ZITADEL_CLIENT_ID}"
        echo ""
        echo "To get a new secret:"
        echo "  1. Go to http://localhost:8080/ui/console"
        echo "  2. Navigate to Projects > Papermerge > Applications"
        echo "  3. Click on 'Papermerge OAuth2-Proxy'"
        echo "  4. Regenerate the client secret"
        echo "  5. Update .env and restart: docker compose restart proxy"
        echo ""
    fi
else
    echo "❌ ERROR: Provisioning failed"
    echo ""
    echo "Check the provisioner logs with:"
    echo "  docker compose -f docker-compose.yaml logs provisioner"
    echo ""
    exit 1
fi
