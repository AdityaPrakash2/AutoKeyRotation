#!/bin/bash
set -e

echo "=== Updating Keycloak Client for Web Application ==="
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

# Get client ID
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

# Update client for web application
echo "Updating client for web application..."
curl -s -X PUT \
  "http://keycloak:8080/admin/realms/${REALM:-fresh-realm}/clients/$CLIENT_UUID" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "clientId": "'"${CLIENT_ID:-fresh-client}"'",
    "name": "'"${CLIENT_ID:-fresh-client}"'",
    "description": "Managed client with secret in Vault",
    "enabled": true,
    "clientAuthenticatorType": "client-secret",
    "redirectUris": ["http://localhost:5001/auth", "http://localhost:5001/*"],
    "webOrigins": ["*"],
    "publicClient": false,
    "protocol": "openid-connect",
    "directAccessGrantsEnabled": true,
    "serviceAccountsEnabled": true,
    "standardFlowEnabled": true,
    "authorizationServicesEnabled": false
  }' > /dev/null

echo "✅ Client updated successfully"

# Create a test user if not exists
echo "Creating test user if not exists..."
TEST_USER_EXISTS=$(curl -s -X GET \
  "http://keycloak:8080/admin/realms/${REALM:-fresh-realm}/users?username=testuser" \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.[0].id // empty')

if [ -z "$TEST_USER_EXISTS" ]; then
  echo "Creating test user..."
  curl -s -X POST \
    "http://keycloak:8080/admin/realms/${REALM:-fresh-realm}/users" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{
      "username": "testuser",
      "enabled": true,
      "emailVerified": true,
      "firstName": "Test",
      "lastName": "User",
      "email": "testuser@example.com",
      "credentials": [
        {
          "type": "password",
          "value": "password",
          "temporary": false
        }
      ]
    }' > /dev/null
  echo "✅ Test user created"
else
  echo "Test user already exists"
fi

echo "Client has been updated for web application authentication!"
echo "You can now use the Flask app to login with Keycloak." 