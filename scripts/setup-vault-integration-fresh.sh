#!/bin/bash
set -e

echo "=== Setting up Vault Integration with Fresh Realm ==="
echo "Realm: ${REALM:-fresh-realm}"
echo "Client ID: ${CLIENT_ID:-fresh-client}"
echo "Vault Path: kv/data/keycloak/clients/${REALM:-fresh-realm}/${CLIENT_ID:-fresh-client}"

# Get admin token from Keycloak
echo "Getting admin token from Keycloak..."
ADMIN_TOKEN=$(curl -s -X POST \
  "http://keycloak:8080/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=${KEYCLOAK_ADMIN:-admin}" \
  -d "password=${KEYCLOAK_ADMIN_PASSWORD:-admin}" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | jq -r '.access_token')

if [ -z "$ADMIN_TOKEN" ] || [ "$ADMIN_TOKEN" == "null" ]; then
  echo "Failed to get admin token"
  exit 1
fi

# Get client ID
echo "Getting client ID..."
CLIENT_UUID=$(curl -s -X GET \
  "http://keycloak:8080/admin/realms/${REALM:-fresh-realm}/clients" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" | \
  jq -r ".[] | select(.clientId == \"${CLIENT_ID:-fresh-client}\") | .id")

if [ -z "$CLIENT_UUID" ] || [ "$CLIENT_UUID" == "null" ]; then
  echo "Failed to get client UUID"
  exit 1
fi

echo "Internal client ID: $CLIENT_UUID"

# Generate a new client secret first
echo "Generating a new client secret..."
curl -s -X POST \
  "http://keycloak:8080/admin/realms/${REALM:-fresh-realm}/clients/$CLIENT_UUID/client-secret" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" > /dev/null

# Wait a moment for the secret to be available
sleep 3

# Get client secret from Keycloak
echo "Getting client secret from Keycloak..."
MAX_RETRIES=10
RETRY_COUNT=0
CLIENT_SECRET=""

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  CLIENT_SECRET=$(curl -s -X GET \
    "http://keycloak:8080/admin/realms/${REALM:-fresh-realm}/clients/$CLIENT_UUID/client-secret" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json" | \
    jq -r '.value')

  if [ -z "$CLIENT_SECRET" ] || [ "$CLIENT_SECRET" == "null" ]; then
    echo "Attempt $((RETRY_COUNT+1))/$MAX_RETRIES: Client secret not available yet, retrying in 2 seconds..."
    RETRY_COUNT=$((RETRY_COUNT+1))
    sleep 2
  else
    break
  fi
done

if [ -z "$CLIENT_SECRET" ] || [ "$CLIENT_SECRET" == "null" ]; then
  echo "Failed to get client secret after $MAX_RETRIES attempts"
  exit 1
fi

echo "Client secret from Keycloak: $CLIENT_SECRET"

# Configure Vault
echo "Configuring Vault..."

# Enable KV secrets engine
echo "Enabling KV secrets engine..."
curl -s -X POST \
  "${VAULT_ADDR:-http://vault:8201}/v1/sys/mounts/kv" \
  -H "X-Vault-Token: ${VAULT_TOKEN:-root}" \
  -H "Content-Type: application/json" \
  -d '{"type": "kv", "options": {"version": "2"}}' || true

# Store client secret in Vault
echo "Storing client secret in Vault..."
curl -s -X POST \
  "${VAULT_ADDR:-http://vault:8201}/v1/kv/data/keycloak/clients/${REALM:-fresh-realm}/${CLIENT_ID:-fresh-client}" \
  -H "X-Vault-Token: ${VAULT_TOKEN:-root}" \
  -H "Content-Type: application/json" \
  -d "{\"data\":{\"client_secret\":\"$CLIENT_SECRET\"}}" > /dev/null

echo "✅ Client secret stored in Vault at path: kv/data/keycloak/clients/${REALM:-fresh-realm}/${CLIENT_ID:-fresh-client}"

# Test retrieving secret from Vault
echo "Testing retrieving secret from Vault..."
VAULT_SECRET=$(curl -s -X GET \
  "${VAULT_ADDR:-http://vault:8201}/v1/kv/data/keycloak/clients/${REALM:-fresh-realm}/${CLIENT_ID:-fresh-client}" \
  -H "X-Vault-Token: ${VAULT_TOKEN:-root}" | \
  jq -r '.data.data.client_secret')

if [ -z "$VAULT_SECRET" ] || [ "$VAULT_SECRET" == "null" ]; then
  echo "Failed to retrieve client secret from Vault"
  exit 1
fi

echo "✅ Secret retrieved successfully from Vault"

# Test authentication with secret from Vault
echo "Testing authentication with secret from Vault..."
TOKEN=$(curl -s -X POST \
  "http://keycloak:8080/realms/${REALM:-fresh-realm}/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=${CLIENT_ID:-fresh-client}" \
  -d "client_secret=$VAULT_SECRET" \
  -d "grant_type=client_credentials")

if echo "$TOKEN" | jq -e '.access_token' > /dev/null; then
  echo "✅ Authentication successful with secret from Vault!"
  echo "Token expires in: $(echo "$TOKEN" | jq -r '.expires_in') seconds"
  echo "Token: $(echo "$TOKEN" | jq -r '.access_token' | head -c 400)..."
  echo "Token payload:"
  echo "$TOKEN" | jq -r '.access_token' | cut -d'.' -f2 | base64 -d 2>/dev/null | jq .
else
  echo "❌ Authentication failed with secret from Vault"
  echo "$TOKEN"
  exit 1
fi

echo "Vault integration set up successfully!" 