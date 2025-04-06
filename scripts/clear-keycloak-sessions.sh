#!/bin/bash
set -e

echo "=== Clearing Keycloak Sessions ==="
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

# Get users from the realm
echo "Getting users from realm..."
USERS=$(curl -s -X GET \
  "http://keycloak:8080/admin/realms/${REALM:-fresh-realm}/users" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json")

# Log out all users
echo "Logging out all users..."
echo "$USERS" | jq -c '.[]' | while read -r user; do
  USER_ID=$(echo "$user" | jq -r '.id')
  USER_NAME=$(echo "$user" | jq -r '.username')
  
  echo "Logging out user: $USER_NAME ($USER_ID)"
  curl -s -X POST \
    "http://keycloak:8080/admin/realms/${REALM:-fresh-realm}/users/$USER_ID/logout" \
    -H "Authorization: Bearer $ADMIN_TOKEN" \
    -H "Content-Type: application/json"
done

# Try to logout all client sessions too
echo "Logging out all client sessions..."
curl -s -X POST \
  "http://keycloak:8080/admin/realms/${REALM:-fresh-realm}/clients/$CLIENT_UUID/logout-all" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" || echo "Client session logout may not be supported"

echo "✅ Successfully cleared all Keycloak sessions" 