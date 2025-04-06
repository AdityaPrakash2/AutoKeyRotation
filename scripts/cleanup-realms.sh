#!/bin/bash
set -e

echo "=== Cleaning Up Unnecessary Realms ==="

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

# List of realms to keep
KEEP_REALMS=("master" "fresh-realm")

# Get all realms
echo "Getting list of all realms..."
REALMS=$(curl -s -X GET \
  "http://keycloak:8080/admin/realms" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" | \
  jq -r '.[].realm')

# Delete unnecessary realms
for REALM in $REALMS; do
  KEEP=false
  for KEEP_REALM in "${KEEP_REALMS[@]}"; do
    if [ "$REALM" == "$KEEP_REALM" ]; then
      KEEP=true
      break
    fi
  done

  if [ "$KEEP" == "false" ]; then
    echo "Deleting realm: $REALM"
    curl -s -X DELETE \
      "http://keycloak:8080/admin/realms/$REALM" \
      -H "Authorization: Bearer $ADMIN_TOKEN"
    echo "✅ Realm $REALM deleted"
  else
    echo "Keeping realm: $REALM"
  fi
done

echo "Realm cleanup completed successfully!" 