#!/bin/bash
set -e

echo "=== Rotating Client Secret ==="
echo "Realm: ${REALM:-fresh-realm}"
echo "Client ID: ${CLIENT_ID:-fresh-client}"
echo "Vault Path: kv/data/keycloak/clients/${REALM:-fresh-realm}/${CLIENT_ID:-fresh-client}"

# Get admin token
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

# Get current client secret from Keycloak
echo "Getting current client secret from Keycloak..."
MAX_RETRIES=10
RETRY_COUNT=0
CURRENT_SECRET=""

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  CURRENT_SECRET=$(curl -s -X GET \
    "http://keycloak:8080/admin/realms/${REALM:-fresh-realm}/clients/$CLIENT_UUID/client-secret" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json" | \
    jq -r '.value')

  if [ -z "$CURRENT_SECRET" ] || [ "$CURRENT_SECRET" == "null" ]; then
    echo "Attempt $((RETRY_COUNT+1))/$MAX_RETRIES: Client secret not available yet, retrying in 2 seconds..."
    RETRY_COUNT=$((RETRY_COUNT+1))
    sleep 2
  else
    break
  fi
done

if [ -z "$CURRENT_SECRET" ] || [ "$CURRENT_SECRET" == "null" ]; then
  echo "Failed to get client secret after $MAX_RETRIES attempts"
  exit 1
fi

# Get current client secret from Vault
echo "Getting current client secret from Vault..."
VAULT_SECRET=$(curl -s -X GET \
  "${VAULT_ADDR:-http://vault:8201}/v1/kv/data/keycloak/clients/${REALM:-fresh-realm}/${CLIENT_ID:-fresh-client}" \
  -H "X-Vault-Token: ${VAULT_TOKEN:-root}" | \
  jq -r '.data.data.client_secret')

if [ -z "$VAULT_SECRET" ] || [ "$VAULT_SECRET" == "null" ]; then
  echo "Failed to get current client secret from Vault"
  exit 1
fi

# Check if secrets match
if [ "$CURRENT_SECRET" == "$VAULT_SECRET" ]; then
  echo "✅ Current secrets match between Keycloak and Vault"
else
  echo "⚠️ WARNING: Current secrets do not match between Keycloak and Vault"
  echo "Keycloak: $CURRENT_SECRET"
  echo "Vault: $VAULT_SECRET"
fi

# Generate new client secret
echo "Generating new client secret..."
NEW_SECRET=$(curl -s -X POST \
  "http://keycloak:8080/admin/realms/${REALM:-fresh-realm}/clients/$CLIENT_UUID/client-secret" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" | \
  jq -r '.value')

if [ -z "$NEW_SECRET" ] || [ "$NEW_SECRET" == "null" ]; then
  echo "Failed to generate new client secret"
  exit 1
fi

echo "New client secret: $NEW_SECRET"

# Store new client secret in Vault
echo "Storing new client secret in Vault..."
curl -s -X POST \
  "${VAULT_ADDR:-http://vault:8201}/v1/kv/data/keycloak/clients/${REALM:-fresh-realm}/${CLIENT_ID:-fresh-client}" \
  -H "X-Vault-Token: ${VAULT_TOKEN:-root}" \
  -H "Content-Type: application/json" \
  -d "{\"data\":{\"client_secret\":\"$NEW_SECRET\"}}" > /dev/null

echo "✅ New client secret stored in Vault at path: kv/data/keycloak/clients/${REALM:-fresh-realm}/${CLIENT_ID:-fresh-client}"

# Test authentication with new client secret
echo "Testing authentication with new client secret..."
TOKEN=$(curl -s -X POST \
  "http://keycloak:8080/realms/${REALM:-fresh-realm}/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=${CLIENT_ID:-fresh-client}" \
  -d "client_secret=$NEW_SECRET" \
  -d "grant_type=client_credentials")

if echo "$TOKEN" | jq -e '.access_token' > /dev/null; then
  echo "✅ Authentication successful with new client secret!"
  echo "Token expires in: $(echo "$TOKEN" | jq -r '.expires_in') seconds"
else
  echo "❌ Authentication failed with new client secret"
  echo "$TOKEN"
  exit 1
fi

# Verify old client secret no longer works
echo "Verifying that old client secret no longer works..."
OLD_TOKEN=$(curl -s -X POST \
  "http://keycloak:8080/realms/${REALM:-fresh-realm}/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=${CLIENT_ID:-fresh-client}" \
  -d "client_secret=$CURRENT_SECRET" \
  -d "grant_type=client_credentials")

if echo "$OLD_TOKEN" | jq -e '.error' > /dev/null; then
  echo "✅ Old client secret no longer works (expected behavior)"
  echo "Error: $(echo "$OLD_TOKEN" | jq -r '.error_description')"
else
  echo "⚠️ WARNING: Old client secret still works, which should not happen"
fi

echo "Client secret rotation completed successfully!" 