#!/bin/bash
set -e

echo "=== Creating Fresh Realm and Client ==="
echo "Realm: ${REALM:-fresh-realm}"
echo "Client ID: ${CLIENT_ID:-fresh-client}"

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

# Check if realm already exists
echo "Checking if realm already exists..."
REALM_EXISTS=$(curl -s -o /dev/null -w "%{http_code}" \
  "http://keycloak:8080/admin/realms/${REALM:-fresh-realm}" \
  -H "Authorization: Bearer $ADMIN_TOKEN")

if [ "$REALM_EXISTS" == "200" ]; then
  echo "Realm already exists, deleting it..."
  curl -s -X DELETE \
    "http://keycloak:8080/admin/realms/${REALM:-fresh-realm}" \
    -H "Authorization: Bearer $ADMIN_TOKEN"
  echo "Realm deleted"
  # Wait a moment for the deletion to complete
  sleep 2
fi

# Create new realm
echo "Creating new realm..."
curl -s -X POST \
  "http://keycloak:8080/admin/realms" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "realm": "'"${REALM:-fresh-realm}"'",
    "enabled": true,
    "accessTokenLifespan": 300,
    "ssoSessionIdleTimeout": 1800,
    "ssoSessionMaxLifespan": 36000,
    "displayName": "Fresh Realm",
    "displayNameHtml": "<strong>Fresh Realm</strong>",
    "loginTheme": "keycloak",
    "emailTheme": "keycloak"
  }' > /dev/null
echo "✅ Realm created successfully"

# Create test user
echo "Creating test user..."
curl -s -X POST \
  "http://keycloak:8080/admin/realms/${REALM:-fresh-realm}/users" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "test-user",
    "email": "test@example.com",
    "enabled": true,
    "credentials": [
      {
        "type": "password",
        "value": "password",
        "temporary": false
      }
    ]
  }' > /dev/null
echo "Test user created"

# Create new client
echo "Creating new client..."
curl -s -X POST \
  "http://keycloak:8080/admin/realms/${REALM:-fresh-realm}/clients" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "clientId": "'"${CLIENT_ID:-fresh-client}"'",
    "name": "'"${CLIENT_ID:-fresh-client}"'",
    "description": "Managed client with secret in Vault",
    "enabled": true,
    "clientAuthenticatorType": "client-secret",
    "secret": "",
    "redirectUris": ["*"],
    "webOrigins": ["*"],
    "publicClient": false,
    "protocol": "openid-connect",
    "directAccessGrantsEnabled": true,
    "serviceAccountsEnabled": true,
    "standardFlowEnabled": true,
    "implicitFlowEnabled": false
  }' > /dev/null

# Add a delay to ensure the client is fully created and the secret is generated
sleep 5

# Get internal client ID
echo "Getting internal client ID..."
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

# Get client secret
echo "Getting client secret..."
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

echo "Client secret: $CLIENT_SECRET"

# Test authentication with client secret
echo "Testing authentication with client secret..."
TOKEN=$(curl -s -X POST \
  "http://keycloak:8080/realms/${REALM:-fresh-realm}/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=${CLIENT_ID:-fresh-client}" \
  -d "client_secret=$CLIENT_SECRET" \
  -d "grant_type=client_credentials")

if echo "$TOKEN" | jq -e '.access_token' > /dev/null; then
  echo "✅ Authentication successful!"
  echo "Token expires in: $(echo "$TOKEN" | jq -r '.expires_in') seconds"
  echo "Token: $(echo "$TOKEN" | jq -r '.access_token' | head -c 400)..."
  echo "Token payload:"
  echo "$TOKEN" | jq -r '.access_token' | cut -d'.' -f2 | base64 -d 2>/dev/null | jq .
else
  echo "❌ Authentication failed"
  echo "$TOKEN"
  exit 1
fi

echo "Fresh realm and client created successfully!" 