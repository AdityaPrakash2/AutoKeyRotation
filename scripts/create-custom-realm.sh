#!/bin/bash
set -e

# Configuration
KEYCLOAK_URL=${KEYCLOAK_URL:-"http://keycloak:8080"}
KEYCLOAK_ADMIN=${KEYCLOAK_ADMIN:-"admin"}
KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD:-"admin"}
VAULT_ADDR=${VAULT_ADDR:-"http://vault:8201"}
VAULT_TOKEN=${VAULT_TOKEN:-"root"}
REALM_NAME="vault-integrated"

# Function to get admin token
get_admin_token() {
  curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "username=${KEYCLOAK_ADMIN}" \
    -d "password=${KEYCLOAK_ADMIN_PASSWORD}" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" | jq -r '.access_token'
}

echo "Obtaining admin token from Keycloak..."
TOKEN=$(get_admin_token)

if [ -z "$TOKEN" ] || [ "$TOKEN" == "null" ]; then
  echo "Error: Failed to obtain admin token from Keycloak."
  exit 1
fi

echo "Admin token obtained successfully."

# Check if the realm already exists
echo "Checking if realm already exists..."
EXISTING_REALMS=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json")

if echo "$EXISTING_REALMS" | jq -r '.[].realm' | grep -q "$REALM_NAME"; then
  echo "Realm $REALM_NAME already exists. Deleting it..."
  curl -s -X DELETE "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}" \
    -H "Authorization: Bearer ${TOKEN}"
  echo "Realm deleted."
  
  # Wait a moment for the deletion to take effect
  sleep 3
fi

# Create a new realm
echo "Creating new realm: ${REALM_NAME}..."
NEW_REALM_JSON=$(cat <<EOF
{
  "realm": "${REALM_NAME}",
  "enabled": true,
  "displayName": "Vault Integrated Demo",
  "displayNameHtml": "<div class=\"kc-logo-text\"><span>Vault Integrated Demo</span></div>",
  "sslRequired": "external",
  "registrationAllowed": true,
  "loginWithEmailAllowed": true,
  "duplicateEmailsAllowed": false,
  "resetPasswordAllowed": true,
  "editUsernameAllowed": false,
  "bruteForceProtected": true,
  "accessTokenLifespan": 300
}
EOF
)

CREATE_REALM_RESULT=$(curl -s -X POST "${KEYCLOAK_URL}/admin/realms" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$NEW_REALM_JSON")

if [ $? -ne 0 ] || echo "$CREATE_REALM_RESULT" | grep -q "error"; then
  echo "Error creating realm: $CREATE_REALM_RESULT"
  exit 1
fi

echo "New realm created successfully."

# Fetch key data from Vault
echo "Fetching key data from Vault..."
VAULT_DATA=$(curl -s -H "X-Vault-Token: ${VAULT_TOKEN}" "${VAULT_ADDR}/v1/secret/data/keycloak/keys/signing")
if [ $? -ne 0 ] || echo "$VAULT_DATA" | grep -q "errors"; then
  echo "Error: Failed to fetch key data from Vault."
  echo "Response: $VAULT_DATA"
  exit 1
fi

# Extract active key ID from Vault
ACTIVE_KEY_ID=$(echo "$VAULT_DATA" | jq -r '.data.data.active')
echo "Vault Active key ID: $ACTIVE_KEY_ID"

# Extract the actual key data
KEYS_DATA=$(echo "$VAULT_DATA" | jq -r '.data.data.keys')
ACTIVE_KEY=$(echo "$KEYS_DATA" | jq -r ".[\"$ACTIVE_KEY_ID\"]")

# Get private key and public key
PRIVATE_KEY=$(echo "$ACTIVE_KEY" | jq -r '.privateKey')
PUBLIC_KEY=$(echo "$ACTIVE_KEY" | jq -r '.publicKey')

# Format keys for JSON payload
PRIVATE_KEY_CLEAN=$(echo "$PRIVATE_KEY" | sed ':a;N;$!ba;s/\n/\\n/g')
PUBLIC_KEY_CLEAN=$(echo "$PUBLIC_KEY" | sed ':a;N;$!ba;s/\n/\\n/g')

# Create a new key provider for the realm
echo "Creating Vault Key Provider for the new realm..."
PROVIDER_JSON=$(cat <<EOF
{
  "name": "vault-key-provider",
  "providerId": "rsa",
  "providerType": "org.keycloak.keys.KeyProvider",
  "parentId": "${REALM_NAME}",
  "config": {
    "priority": ["100"],
    "enabled": ["true"],
    "active": ["true"],
    "privateKey": ["${PRIVATE_KEY_CLEAN}"],
    "publicKey": ["${PUBLIC_KEY_CLEAN}"],
    "keyUse": ["SIG"],
    "algorithm": ["RS256"]
  }
}
EOF
)

CREATE_PROVIDER_RESULT=$(curl -v -X POST "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/components" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$PROVIDER_JSON")

echo "Provider creation result: $CREATE_PROVIDER_RESULT"

# Create a second provider as fallback
echo "Creating fallback RSA Generated Provider..."
GENERATED_PROVIDER_JSON=$(cat <<EOF
{
  "name": "fallback-key-provider",
  "providerId": "rsa-generated",
  "providerType": "org.keycloak.keys.KeyProvider",
  "parentId": "${REALM_NAME}",
  "config": {
    "priority": ["200"],
    "enabled": ["true"],
    "active": ["true"],
    "algorithm": ["RS256"],
    "keySize": ["2048"],
    "keyUse": ["SIG"]
  }
}
EOF
)

CREATE_FALLBACK_RESULT=$(curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/components" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$GENERATED_PROVIDER_JSON")

echo "Fallback provider creation result: $CREATE_FALLBACK_RESULT"

# Create a client for testing
echo "Creating test client in new realm..."
CLIENT_JSON=$(cat <<EOF
{
  "clientId": "test-client",
  "enabled": true,
  "publicClient": true,
  "redirectUris": ["*"],
  "webOrigins": ["*"],
  "directAccessGrantsEnabled": true,
  "standardFlowEnabled": true,
  "protocol": "openid-connect"
}
EOF
)

CREATE_CLIENT_RESULT=$(curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$CLIENT_JSON")

echo "Client creation result: $CREATE_CLIENT_RESULT"

# Create test user
echo "Creating test user in new realm..."
USER_JSON=$(cat <<EOF
{
  "username": "testuser",
  "enabled": true,
  "emailVerified": true,
  "firstName": "Test",
  "lastName": "User",
  "email": "test@example.com",
  "credentials": [{
    "type": "password",
    "value": "password",
    "temporary": false
  }]
}
EOF
)

CREATE_USER_RESULT=$(curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$USER_JSON")

echo "User creation result: $CREATE_USER_RESULT"

# Output information
echo "-----------------------------------------------------"
echo "New realm created successfully: ${REALM_NAME}"
echo "-----------------------------------------------------"
echo "Access the realm at: ${KEYCLOAK_URL}/admin/master/console/#/${REALM_NAME}"
echo "Login details:"
echo "  Username: testuser"
echo "  Password: password"
echo "-----------------------------------------------------"
echo "The key providers have been configured. Check the Keys tab in Realm Settings."
echo "-----------------------------------------------------"

# Fetch and display the public keys endpoint for the new realm
echo "Checking for keys in the realm via the public endpoint..."
curl -s "${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/certs" | jq .

echo "Custom realm setup completed!" 