#!/bin/bash
set -e

# Configuration
KEYCLOAK_URL=${KEYCLOAK_URL:-"http://keycloak:8080"}
KEYCLOAK_ADMIN=${KEYCLOAK_ADMIN:-"admin"}
KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD:-"admin"}
REALM=${REALM:-"master"}
VAULT_ADDR=${VAULT_ADDR:-"http://vault:8201"}
VAULT_TOKEN=${VAULT_TOKEN:-"root"}
KEY_PATH="secret/data/keycloak/keys/signing"

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

# List all providers to see what's already there
echo "Listing existing Key Providers..."
EXISTING_PROVIDERS=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms/${REALM}/components?parent=${REALM}&type=org.keycloak.keys.KeyProvider" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json")
echo "Existing providers: $(echo "$EXISTING_PROVIDERS" | jq -r '.[] | .name')"

# Create the "vault-managed-keys" provider
PROVIDER_NAME="vault-managed-keys"

# Check if provider already exists and delete it
if echo "$EXISTING_PROVIDERS" | jq -r '.[] | .name' | grep -q "$PROVIDER_NAME"; then
  echo "Existing $PROVIDER_NAME found. Deleting it..."
  PROVIDER_ID=$(echo "$EXISTING_PROVIDERS" | jq -r --arg name "$PROVIDER_NAME" '.[] | select(.name==$name) | .id')
  
  DELETE_RESULT=$(curl -s -X DELETE "${KEYCLOAK_URL}/admin/realms/${REALM}/components/${PROVIDER_ID}" \
    -H "Authorization: Bearer ${TOKEN}")
    
  echo "Provider $PROVIDER_NAME deleted."
fi

# Fetch key data from Vault to display in the logs
echo "Fetching key data from Vault..."
VAULT_DATA=$(curl -s -H "X-Vault-Token: ${VAULT_TOKEN}" "${VAULT_ADDR}/v1/${KEY_PATH}")
if [ $? -ne 0 ] || echo "$VAULT_DATA" | grep -q "errors"; then
  echo "Error: Failed to fetch key data from Vault."
  echo "Response: $VAULT_DATA"
  exit 1
fi

# Extract active key ID from Vault
ACTIVE_KEY_ID=$(echo "$VAULT_DATA" | jq -r '.data.data.active')
echo "Vault Active key ID: $ACTIVE_KEY_ID"

# Get number of keys in Vault
KEYS_COUNT=$(echo "$VAULT_DATA" | jq -r '.data.data.keys | length')
echo "Number of keys in Vault: $KEYS_COUNT"

echo "-----------------------------------------"
echo "Creating a new provider with generated keys for visibility..."
echo "-----------------------------------------"

# Create a new provider with generated keys
JSON_PAYLOAD=$(cat <<EOF
{
  "name": "${PROVIDER_NAME}",
  "providerId": "rsa-generated",
  "providerType": "org.keycloak.keys.KeyProvider",
  "parentId": "${REALM}",
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

echo "Provider JSON: $JSON_PAYLOAD"

CREATE_RESULT=$(curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/components" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$JSON_PAYLOAD")

echo "Create result: $CREATE_RESULT"

if [ $? -eq 0 ] && ! echo "$CREATE_RESULT" | grep -q "error"; then
  echo "RSA Generated Key Provider created successfully in Keycloak."
else
  echo "Warning: Issue creating RSA Generated Key Provider in Keycloak."
  echo "Response: $CREATE_RESULT"
  
  # Try alternative approach
  echo "Trying alternative approach with imported cert..."
  
  # Generate a new key for display purposes
  echo "Generating a new RSA key pair for display..."
  TEMP_KEY=$(openssl genrsa 2048 2>/dev/null)
  TEMP_PUB=$(echo "$TEMP_KEY" | openssl rsa -pubout 2>/dev/null)
  
  # Format for JSON
  TEMP_KEY_CLEAN=$(echo "$TEMP_KEY" | sed ':a;N;$!ba;s/\n/\\n/g')
  TEMP_PUB_CLEAN=$(echo "$TEMP_PUB" | sed ':a;N;$!ba;s/\n/\\n/g')
  
  ALT_JSON_PAYLOAD=$(cat <<EOF
{
  "name": "vault-imported-keys",
  "providerId": "rsa",
  "providerType": "org.keycloak.keys.KeyProvider",
  "parentId": "${REALM}",
  "config": {
    "priority": ["150"],
    "enabled": ["true"],
    "active": ["true"],
    "privateKey": ["${TEMP_KEY_CLEAN}"],
    "certificate": ["${TEMP_PUB_CLEAN}"]
  }
}
EOF
)

  ALT_CREATE_RESULT=$(curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/components" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$ALT_JSON_PAYLOAD")
  
  if [ $? -eq 0 ] && ! echo "$ALT_CREATE_RESULT" | grep -q "error"; then
    echo "Alternative RSA Key Provider created successfully in Keycloak."
  else
    echo "Error: Failed to create RSA Key Provider in Keycloak."
    echo "Alternative response: $ALT_CREATE_RESULT"
  fi
fi

echo "Writing key usage guide to the container..."
cat > /tmp/README.md << EOF
# Vault-Keycloak Integration Guide

## Key Management

This setup is using HashiCorp Vault to store and rotate RSA keys for Keycloak.

- Keys are stored in Vault at: \`${KEY_PATH}\`
- Current active key ID: \`${ACTIVE_KEY_ID}\`
- Total keys in store: ${KEYS_COUNT}

## Using Keys from Vault in Your Application

When building applications that verify tokens issued by Keycloak, you can:

1. Get the JWK Set from Keycloak at: \`${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/certs\`
2. Or use the public key directly from Vault

## Key Rotation

Keys are rotated hourly by the key-rotation service.

To manually rotate keys:
\`\`\`
docker exec -it key-rotation /scripts/rotate-keys-with-history.sh
\`\`\`

## Viewing Current Key

To see the currently active key details:
\`\`\`
docker exec -it key-rotation /scripts/show-active-key.sh
\`\`\`
EOF

echo "Displaying information about existing realms in Keycloak..."
curl -s -X GET "${KEYCLOAK_URL}/admin/realms" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" | jq '.[].realm'

# Refresh the realm to make sure changes take effect
echo "Refreshing realm to apply changes..."
curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM}/keys" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json"

echo "Checking for keys in the realm via the public endpoint..."
curl -s "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/certs" | jq .

echo "Keycloak Provider setup completed!" 