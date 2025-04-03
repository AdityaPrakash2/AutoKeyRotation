#!/bin/bash

# Configuration
KEYCLOAK_URL=${KEYCLOAK_URL:-"http://keycloak:8080"}
KEYCLOAK_ADMIN=${KEYCLOAK_ADMIN:-"admin"}
KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD:-"admin"}
MAIN_REALM=${REALM:-"master"}
CUSTOM_REALM="vault-integrated"

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

# Trigger key refresh for master realm
echo "Triggering key refresh in Keycloak (${MAIN_REALM} realm)..."
RESULT=$(curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${MAIN_REALM}/keys" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json")

if [ $? -eq 0 ]; then
  echo "Key refresh notification sent to Keycloak master realm successfully."
else
  echo "Error: Failed to send key refresh notification to Keycloak master realm."
  echo "Response: $RESULT"
fi

# Check if the custom realm exists and refresh it as well
echo "Checking if custom realm exists..."
EXISTING_REALMS=$(curl -s -X GET "${KEYCLOAK_URL}/admin/realms" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json")

if echo "$EXISTING_REALMS" | jq -r '.[].realm' | grep -q "$CUSTOM_REALM"; then
  echo "Triggering key refresh in Keycloak (${CUSTOM_REALM} realm)..."
  CUSTOM_RESULT=$(curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${CUSTOM_REALM}/keys" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json")

  if [ $? -eq 0 ]; then
    echo "Key refresh notification sent to Keycloak custom realm successfully."
  else
    echo "Error: Failed to send key refresh notification to Keycloak custom realm."
    echo "Response: $CUSTOM_RESULT"
  fi
  
  # Update the vault-key-provider in the custom realm
  echo "Updating custom realm key provider..."
  /scripts/create-custom-realm.sh
else
  echo "Custom realm does not exist yet. Skipping custom realm key refresh."
fi 