#!/bin/bash
set -e

echo "Waiting for Zitadel to be ready..."
until curl -sf http://localhost:8080/debug/ready > /dev/null 2>&1; do
    echo "Zitadel not ready yet, waiting..."
    sleep 2
done
echo "Zitadel is ready!"

# Additional wait to ensure Zitadel is fully initialized
sleep 5

# Read the PAT token
if [ ! -f /current-dir/admin.pat ]; then
    echo "ERROR: admin.pat not found. Make sure ZITADEL_FIRSTINSTANCE_PATPATH is configured."
    exit 1
fi

PAT=$(cat /current-dir/admin.pat)
echo "PAT token loaded successfully"

# Zitadel API base URL
API_URL="http://localhost:8080"

# The management API needs an organization context in the URL path
# Since we're using IAM_OWNER machine user, we need to work with the admin API
# or figure out the org ID first

# Method 1: Try to get organization from the token introspection
echo "Getting organization context..."

# Get the machine user's details to find the org
USER_RESPONSE=$(curl -s -X GET "${API_URL}/auth/v1/users/me" \
    -H "Authorization: Bearer ${PAT}")

echo "Auth response: $USER_RESPONSE"

# Extract org ID from the response
ORG_ID=$(echo "$USER_RESPONSE" | jq -r '.user.resourceOwner // empty')

# If that didn't work, try getting it from the instance default
if [ -z "$ORG_ID" ]; then
    echo "Trying to get default org from instance..."

    # For Zitadel, we can also list orgs using the admin API
    # But with a fresh instance, there should only be one org

    # Alternative approach: Use the system API to list organizations
    ORGS_RESPONSE=$(curl -s -X POST "${API_URL}/admin/v1/orgs/_search" \
        -H "Authorization: Bearer ${PAT}" \
        -H "Content-Type: application/json" \
        -d '{"limit": 10}')

    echo "Orgs search response: $ORGS_RESPONSE"

    ORG_ID=$(echo "$ORGS_RESPONSE" | jq -r '.result[0].id // empty')
fi

if [ -z "$ORG_ID" ]; then
    echo "ERROR: Could not determine organization ID"
    echo "This usually means the machine user wasn't created properly."
    echo "Check that ZITADEL_FIRSTINSTANCE_PATPATH and related env vars are set in docker-compose."
    exit 1
fi

echo "Using Organization ID: $ORG_ID"

# Now we can work with the management API using this org context
# The management API automatically uses the org from the authenticated user

# Check if project already exists
echo "Checking if Papermerge project already exists..."
PROJECT_RESPONSE=$(curl -s -X POST "${API_URL}/management/v1/projects/_search" \
    -H "Authorization: Bearer ${PAT}" \
    -H "Content-Type: application/json" \
    -H "x-zitadel-orgid: ${ORG_ID}" \
    -d '{
        "queries": [
            {
                "nameQuery": {
                    "name": "Papermerge",
                    "method": "TEXT_QUERY_METHOD_EQUALS"
                }
            }
        ]
    }')

echo "Project search response: $PROJECT_RESPONSE"

PROJECT_ID=$(echo "$PROJECT_RESPONSE" | jq -r '.result[0].id // empty')

if [ -n "$PROJECT_ID" ]; then
    echo "Project already exists with ID: $PROJECT_ID"
else
    echo "Creating Papermerge project..."
    PROJECT_CREATE_RESPONSE=$(curl -s -X POST "${API_URL}/management/v1/projects" \
        -H "Authorization: Bearer ${PAT}" \
        -H "Content-Type: application/json" \
        -H "x-zitadel-orgid: ${ORG_ID}" \
        -d '{
            "name": "Papermerge",
            "projectRoleAssertion": true,
            "projectRoleCheck": false
        }')

    echo "Project create response: $PROJECT_CREATE_RESPONSE"

    PROJECT_ID=$(echo "$PROJECT_CREATE_RESPONSE" | jq -r '.id // empty')
    if [ -z "$PROJECT_ID" ]; then
        echo "ERROR: Could not create project"
        echo "Response: $PROJECT_CREATE_RESPONSE"
        exit 1
    fi
    echo "Project created with ID: $PROJECT_ID"
fi

# Create 'admin' role in the project
echo "Checking if 'admin' role exists..."
ROLES_RESPONSE=$(curl -s -X POST "${API_URL}/management/v1/projects/${PROJECT_ID}/roles/_search" \
    -H "Authorization: Bearer ${PAT}" \
    -H "Content-Type: application/json" \
    -H "x-zitadel-orgid: ${ORG_ID}" \
    -d '{
        "queries": [
            {
                "keyQuery": {
                    "key": "admin",
                    "method": "TEXT_QUERY_METHOD_EQUALS"
                }
            }
        ]
    }')

ROLE_KEY=$(echo "$ROLES_RESPONSE" | jq -r '.result[0].key // empty')

if [ -n "$ROLE_KEY" ]; then
    echo "Role 'admin' already exists"
else
    echo "Creating 'admin' role..."
    ROLE_CREATE_RESPONSE=$(curl -s -X POST "${API_URL}/management/v1/projects/${PROJECT_ID}/roles" \
        -H "Authorization: Bearer ${PAT}" \
        -H "Content-Type: application/json" \
        -H "x-zitadel-orgid: ${ORG_ID}" \
        -d '{
            "roleKey": "admin",
            "displayName": "Administrator",
            "group": ""
        }')
    
    echo "Role create response: $ROLE_CREATE_RESPONSE"
fi

# Check if application already exists
echo "Checking if OAuth2-Proxy application already exists..."
APP_RESPONSE=$(curl -s -X POST "${API_URL}/management/v1/projects/${PROJECT_ID}/apps/_search" \
    -H "Authorization: Bearer ${PAT}" \
    -H "Content-Type: application/json" \
    -H "x-zitadel-orgid: ${ORG_ID}" \
    -d '{
        "queries": [
            {
                "nameQuery": {
                    "name": "Papermerge OAuth2-Proxy",
                    "method": "TEXT_QUERY_METHOD_EQUALS"
                }
            }
        ]
    }')

echo "App search response: $APP_RESPONSE"

APP_ID=$(echo "$APP_RESPONSE" | jq -r '.result[0].id // empty')

if [ -n "$APP_ID" ]; then
    echo "Application already exists with ID: $APP_ID"
    # For existing apps, we need to get the client ID from the app details
    APP_DETAILS=$(curl -s -X GET "${API_URL}/management/v1/projects/${PROJECT_ID}/apps/${APP_ID}" \
        -H "Authorization: Bearer ${PAT}" \
        -H "x-zitadel-orgid: ${ORG_ID}")

    echo "App details response: $APP_DETAILS"

    CLIENT_ID=$(echo "$APP_DETAILS" | jq -r '.app.oidcConfig.clientId // empty')

    if [ -z "$CLIENT_ID" ]; then
        echo "ERROR: Could not get client ID for existing application"
        exit 1
    fi

    echo "WARNING: Application already exists. Client secret cannot be retrieved again."
    echo "If you need a new secret, you must manually regenerate it in the Zitadel console"
    echo "or delete the application and re-run this script."

    # Write what we have to the credentials file
    cat > /current-dir/zitadel-credentials.env << EOF
# Auto-generated Zitadel credentials
# Generated at: $(date)
ZITADEL_CLIENT_ID=${CLIENT_ID}
# Client secret not available for existing applications
# Either use your existing secret or regenerate in Zitadel console
ZITADEL_CLIENT_SECRET=
EOF

    echo "Partial credentials written to zitadel-credentials.env"
    echo "Please manually add the client secret to complete the configuration."

else
    echo "Creating OAuth2-Proxy application..."
    APP_CREATE_RESPONSE=$(curl -s -X POST "${API_URL}/management/v1/projects/${PROJECT_ID}/apps/oidc" \
        -H "Authorization: Bearer ${PAT}" \
        -H "Content-Type: application/json" \
        -H "x-zitadel-orgid: ${ORG_ID}" \
        -d '{
            "name": "Papermerge OAuth2-Proxy",
            "redirectUris": [
                "http://localhost:8081/oauth2/callback"
            ],
            "postLogoutRedirectUris": [
                "http://localhost:8081"
            ],
            "responseTypes": [
                "OIDC_RESPONSE_TYPE_CODE"
            ],
            "grantTypes": [
                "OIDC_GRANT_TYPE_AUTHORIZATION_CODE",
                "OIDC_GRANT_TYPE_REFRESH_TOKEN"
            ],
            "appType": "OIDC_APP_TYPE_WEB",
            "authMethodType": "OIDC_AUTH_METHOD_TYPE_BASIC",
            "version": "OIDC_VERSION_1_0",
            "devMode": false,
            "accessTokenType": "OIDC_TOKEN_TYPE_BEARER",
            "idTokenRoleAssertion": true,
            "idTokenUserinfoAssertion": true,
            "accessTokenRoleAssertion": true,
            "skipNativeAppSuccessPage": false
        }')

    echo "App create response: $APP_CREATE_RESPONSE"

    CLIENT_ID=$(echo "$APP_CREATE_RESPONSE" | jq -r '.clientId // empty')
    CLIENT_SECRET=$(echo "$APP_CREATE_RESPONSE" | jq -r '.clientSecret // empty')

    if [ -z "$CLIENT_ID" ]; then
        echo "ERROR: Could not create application"
        echo "Response: $APP_CREATE_RESPONSE"
        exit 1
    fi

    echo "Application created successfully!"
    echo "Client ID: $CLIENT_ID"
    echo "Client Secret: ${CLIENT_SECRET:0:10}... (truncated)"

    # Write credentials to a file
    cat > /current-dir/zitadel-credentials.env << EOF
# Auto-generated Zitadel credentials
# Generated at: $(date)
ZITADEL_CLIENT_ID=${CLIENT_ID}
ZITADEL_CLIENT_SECRET=${CLIENT_SECRET}
EOF

    echo "Credentials written to zitadel-credentials.env"
fi

# Grant admin role to root user
echo "Finding root user..."
USERS_RESPONSE=$(curl -s -X POST "${API_URL}/management/v1/users/_search" \
    -H "Authorization: Bearer ${PAT}" \
    -H "Content-Type: application/json" \
    -H "x-zitadel-orgid: ${ORG_ID}" \
    -d '{
        "queries": [
            {
                "userNameQuery": {
                    "userName": "root@my-organization.localhost",
                    "method": "TEXT_QUERY_METHOD_EQUALS"
                }
            }
        ]
    }')

USER_ID=$(echo "$USERS_RESPONSE" | jq -r '.result[0].id // empty')

if [ -n "$USER_ID" ]; then
    echo "Root user ID: $USER_ID"

    # Check if user already has the grant
    USER_GRANTS=$(curl -s -X POST "${API_URL}/management/v1/users/${USER_ID}/grants/_search" \
        -H "Authorization: Bearer ${PAT}" \
        -H "Content-Type: application/json" \
        -H "x-zitadel-orgid: ${ORG_ID}" \
        -d "{
            \"queries\": [
                {
                    \"projectIdQuery\": {
                        \"projectId\": \"${PROJECT_ID}\"
                    }
                }
            ]
        }")

    GRANT_ID=$(echo "$USER_GRANTS" | jq -r '.result[0].id // empty')

    if [ -n "$GRANT_ID" ]; then
        echo "User already has grant to project"
    else
        echo "Granting admin role to root user..."
        USER_GRANT_RESPONSE=$(curl -s -X POST "${API_URL}/management/v1/users/${USER_ID}/grants" \
            -H "Authorization: Bearer ${PAT}" \
            -H "Content-Type: application/json" \
            -H "x-zitadel-orgid: ${ORG_ID}" \
            -d "{
                \"projectId\": \"${PROJECT_ID}\",
                \"roleKeys\": [\"admin\"]
            }")

        echo "User grant response: $USER_GRANT_RESPONSE"
    fi
else
    echo "WARNING: Could not find root user to grant admin role"
fi

# Create action to add standard 'roles' claim
echo "Creating token action to add roles claim..."
ACTION_CREATE=$(curl -s -X POST "${API_URL}/management/v1/actions" \
    -H "Authorization: Bearer ${PAT}" \
    -H "Content-Type: application/json" \
    -H "x-zitadel-orgid: ${ORG_ID}" \
    -d '{
        "name": "add-roles-claim",
        "script": "function addRoles(ctx, api) { if (ctx.v1.claims[\"urn:zitadel:iam:org:project:roles\"]) { var projectRoles = ctx.v1.claims[\"urn:zitadel:iam:org:project:roles\"]; var roles = Object.keys(projectRoles); api.v1.claims.setClaim(\"roles\", roles); } }",
        "timeout": "10s",
        "allowedToFail": false
    }')

ACTION_ID=$(echo "$ACTION_CREATE" | jq -r '.id // empty')

if [ -n "$ACTION_ID" ]; then
    echo "Action created with ID: $ACTION_ID"

    # Bind action to complement token flow
    echo "Binding action to token flow..."
    curl -s -X POST "${API_URL}/management/v1/flows/2/trigger/4/actions" \
        -H "Authorization: Bearer ${PAT}" \
        -H "Content-Type: application/json" \
        -H "x-zitadel-orgid: ${ORG_ID}" \
        -d "{
            \"actionId\": \"${ACTION_ID}\"
        }"

    echo "Action bound to token complement flow"
else
    echo "WARNING: Could not create action"
fi

echo "Provisioning complete!"
