#!/bin/bash
set -e

echo "=========================================================="
echo "           CLIENT SECRET ROTATION TESTING SUITE           "
echo "=========================================================="

# Configuration
KEYCLOAK_URL=${KEYCLOAK_URL:-"http://keycloak:8080"}
EXTERNAL_KEYCLOAK_URL=${EXTERNAL_KEYCLOAK_URL:-"http://localhost:8080"}
VAULT_ADDR=${VAULT_ADDR:-"http://vault:8201"}
VAULT_TOKEN=${VAULT_TOKEN:-"root"}
REALM=${REALM:-"fresh-realm"}
CLIENT_ID=${CLIENT_ID:-"fresh-client"}
TEST_USER=${TEST_USER:-"test-user"}
TEST_PASSWORD=${TEST_PASSWORD:-"password"}

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

test_success() {
  echo -e "${GREEN}✓ $1${NC}"
}

test_failure() {
  echo -e "${RED}✗ $1${NC}"
  if [ -n "$2" ]; then
    echo -e "${RED}  Details: $2${NC}"
  fi
  TEST_FAILURES=$((TEST_FAILURES + 1))
}

test_warning() {
  echo -e "${YELLOW}⚠ $1${NC}"
}

# Initialize test failure counter
TEST_FAILURES=0

echo -e "\n📋 RUNNING FUNCTIONAL TESTS"
echo "-----------------------------------------------------------"

echo -e "\n🔍 Test 1: Verify Keycloak can connect to Vault"
# Get admin token from Keycloak
ADMIN_TOKEN=$(curl -s -X POST \
  "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=${KEYCLOAK_ADMIN:-admin}" \
  -d "password=${KEYCLOAK_ADMIN_PASSWORD:-admin}" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" | jq -r '.access_token')

if [ -z "$ADMIN_TOKEN" ] || [ "$ADMIN_TOKEN" == "null" ]; then
  test_failure "Failed to get admin token from Keycloak" "Check Keycloak admin credentials"
  exit 1
else
  test_success "Retrieved admin token from Keycloak"
fi

echo -e "\n🔍 Test 2: Get client UUID from Keycloak"
CLIENT_UUID=$(curl -s -X GET \
  "${KEYCLOAK_URL}/admin/realms/${REALM}/clients" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" | \
  jq -r ".[] | select(.clientId == \"${CLIENT_ID}\") | .id")

if [ -z "$CLIENT_UUID" ] || [ "$CLIENT_UUID" == "null" ]; then
  test_failure "Failed to get client UUID" "Client ${CLIENT_ID} might not exist in realm ${REALM}"
  exit 1
else
  test_success "Retrieved client UUID: $CLIENT_UUID"
fi

echo -e "\n🔍 Test 3: Get client secret from Keycloak"
KEYCLOAK_SECRET=$(curl -s -X GET \
  "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${CLIENT_UUID}/client-secret" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" | \
  jq -r '.value')

if [ -z "$KEYCLOAK_SECRET" ] || [ "$KEYCLOAK_SECRET" == "null" ]; then
  test_failure "Failed to get client secret from Keycloak"
  exit 1
else
  test_success "Retrieved client secret from Keycloak: ${KEYCLOAK_SECRET:0:5}..."
fi

echo -e "\n🔍 Test 4: Get client secret from Vault"
VAULT_SECRET=$(curl -s -X GET \
  "${VAULT_ADDR}/v1/kv/data/keycloak/clients/${REALM}/${CLIENT_ID}" \
  -H "X-Vault-Token: ${VAULT_TOKEN}" | \
  jq -r '.data.data.client_secret')

if [ -z "$VAULT_SECRET" ] || [ "$VAULT_SECRET" == "null" ]; then
  test_failure "Failed to get client secret from Vault"
  exit 1
else
  test_success "Retrieved client secret from Vault: ${VAULT_SECRET:0:5}..."
fi

echo -e "\n🔍 Test 5: Verify client secrets match between Keycloak and Vault"
if [ "$KEYCLOAK_SECRET" == "$VAULT_SECRET" ]; then
  test_success "Client secrets match between Keycloak and Vault"
else
  test_failure "Client secrets do not match between Keycloak and Vault" "Keycloak: ${KEYCLOAK_SECRET:0:5}... Vault: ${VAULT_SECRET:0:5}..."
fi

echo -e "\n🔍 Test 6: Verify JWT token issuance with current client secret"
TOKEN_RESPONSE=$(curl -s -X POST \
  "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=${CLIENT_ID}" \
  -d "client_secret=${VAULT_SECRET}" \
  -d "scope=openid")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" == "null" ]; then
  test_failure "Failed to get access token with client secret" "Response: $TOKEN_RESPONSE"
else
  test_success "Successfully received access token: ${ACCESS_TOKEN:0:10}..."
  
  # Verify token signature and claims
  # Parse token header
  TOKEN_HEADER=$(echo $ACCESS_TOKEN | cut -d. -f1 | base64 -d 2>/dev/null || true)
  # Parse token payload
  TOKEN_PAYLOAD=$(echo $ACCESS_TOKEN | cut -d. -f2 | base64 -d 2>/dev/null || true)
  
  # Verify issuer
  TOKEN_ISSUER=$(echo "$TOKEN_PAYLOAD" | jq -r '.iss')
  if [[ "$TOKEN_ISSUER" == *"${REALM}"* ]]; then
    test_success "JWT token has correct issuer: $TOKEN_ISSUER"
  else
    test_failure "JWT token has incorrect issuer" "Expected: contains ${REALM}, Got: $TOKEN_ISSUER"
  fi
  
  # Verify client ID - checking azp (authorized party) which is more reliable for client credentials
  TOKEN_CLIENT=$(echo "$TOKEN_PAYLOAD" | jq -r '.azp // .client_id')
  if [[ "$TOKEN_CLIENT" == "${CLIENT_ID}" ]]; then
    test_success "JWT token has correct client identifier: $TOKEN_CLIENT"
  else
    echo "Token payload for debugging:"
    echo "$TOKEN_PAYLOAD" | jq .
    test_failure "JWT token has incorrect client identifier" "Expected: ${CLIENT_ID}, Got: $TOKEN_CLIENT"
  fi
  
  # Verify token expiration
  TOKEN_EXP=$(echo "$TOKEN_PAYLOAD" | jq -r '.exp')
  CURRENT_TIME=$(date +%s)
  if [ $TOKEN_EXP -gt $CURRENT_TIME ]; then
    test_success "JWT token has valid expiration time"
  else
    test_failure "JWT token has expired" "Expiration: $TOKEN_EXP, Current time: $CURRENT_TIME"
  fi
fi

echo -e "\n📋 RUNNING SECURITY TESTS"
echo "-----------------------------------------------------------"

echo -e "\n🔍 Test 7: Rotate client secret and verify old secret no longer works"
echo "Rotating client secret..."

# Generate new client secret
NEW_SECRET_RESPONSE=$(curl -s -X POST \
  "${KEYCLOAK_URL}/admin/realms/${REALM}/clients/${CLIENT_UUID}/client-secret" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json")

NEW_SECRET=$(echo "$NEW_SECRET_RESPONSE" | jq -r '.value')

if [ -z "$NEW_SECRET" ] || [ "$NEW_SECRET" == "null" ]; then
  test_failure "Failed to generate new client secret" "Response: $NEW_SECRET_RESPONSE"
  exit 1
else
  test_success "Generated new client secret: ${NEW_SECRET:0:5}..."
fi

# Store the new secret in Vault
VAULT_STORE_RESPONSE=$(curl -s -X POST \
  "${VAULT_ADDR}/v1/kv/data/keycloak/clients/${REALM}/${CLIENT_ID}" \
  -H "X-Vault-Token: ${VAULT_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"data\":{\"client_secret\":\"$NEW_SECRET\"}}")

if echo "$VAULT_STORE_RESPONSE" | jq -e '.errors' > /dev/null; then
  test_failure "Failed to store new client secret in Vault" "Response: $VAULT_STORE_RESPONSE"
else
  test_success "Successfully stored new client secret in Vault"
fi

# Try to authenticate with old secret
OLD_SECRET_TEST=$(curl -s -X POST \
  "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=${CLIENT_ID}" \
  -d "client_secret=${KEYCLOAK_SECRET}" \
  -d "scope=openid")

if echo "$OLD_SECRET_TEST" | jq -e '.error' > /dev/null; then
  test_success "Old client secret no longer works (expected behavior)"
else
  test_failure "Old client secret still works after rotation" "Response: $OLD_SECRET_TEST"
fi

echo -e "\n🔍 Test 8: Test Vault access control policies"
# Try to access a path not allowed by the policy
UNAUTHORIZED_PATH_RESPONSE=$(curl -s -X GET \
  "${VAULT_ADDR}/v1/sys/mounts" \
  -H "X-Vault-Token: ${VAULT_TOKEN}")

if echo "$UNAUTHORIZED_PATH_RESPONSE" | jq -e '.data' > /dev/null; then
  test_warning "Root token has full access (expected in development). In production, use a limited token."
else
  test_success "Vault policy restricts access to unauthorized paths"
fi

echo -e "\n📋 RUNNING INTEGRATION TESTS"
echo "-----------------------------------------------------------"

echo -e "\n🔍 Test 9: Verify authentication with new client secret"
NEW_TOKEN_RESPONSE=$(curl -s -X POST \
  "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=${CLIENT_ID}" \
  -d "client_secret=${NEW_SECRET}" \
  -d "scope=openid")

NEW_ACCESS_TOKEN=$(echo "$NEW_TOKEN_RESPONSE" | jq -r '.access_token')

if [ -z "$NEW_ACCESS_TOKEN" ] || [ "$NEW_ACCESS_TOKEN" == "null" ]; then
  test_failure "Failed to get access token with new client secret" "Response: $NEW_TOKEN_RESPONSE"
else
  test_success "Successfully received access token with new client secret: ${NEW_ACCESS_TOKEN:0:10}..."
fi

echo -e "\n🔍 Test 10: Simulate client application retrieving latest secret from Vault"
LATEST_VAULT_SECRET=$(curl -s -X GET \
  "${VAULT_ADDR}/v1/kv/data/keycloak/clients/${REALM}/${CLIENT_ID}" \
  -H "X-Vault-Token: ${VAULT_TOKEN}" | \
  jq -r '.data.data.client_secret')

if [ -z "$LATEST_VAULT_SECRET" ] || [ "$LATEST_VAULT_SECRET" == "null" ]; then
  test_failure "Failed to get latest client secret from Vault"
else
  test_success "Client application can retrieve latest secret: ${LATEST_VAULT_SECRET:0:5}..."
  
  # Verify latest secret matches the new one
  if [ "$LATEST_VAULT_SECRET" == "$NEW_SECRET" ]; then
    test_success "Latest Vault secret matches the newly generated secret"
  else
    test_failure "Latest Vault secret does not match newly generated secret" "Latest: ${LATEST_VAULT_SECRET:0:5}..., New: ${NEW_SECRET:0:5}..."
  fi
fi

echo -e "\n🔍 Test 11: Verify user authentication flows are unaffected by secret rotation"
# Get code flow URL for user login
AUTH_URL="${EXTERNAL_KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/auth?client_id=${CLIENT_ID}&redirect_uri=http://localhost:5001/auth&response_type=code&scope=openid"
echo "User authorization URL: $AUTH_URL"
test_warning "Manual verification required: User authentication flows must be tested in a browser"
echo "To test user authentication:"
echo "1. Open browser to: $AUTH_URL"
echo "2. Log in with test user: ${TEST_USER} / ${TEST_PASSWORD}"
echo "3. Verify successful login and redirection"

echo -e "\n🔍 Test 12: Test automated rotation script"
echo "Running full rotation script..."
ROTATION_OUTPUT=$(sh /scripts/rotate-client-secret.sh)
ROTATION_SUCCESS=$?

if [ $ROTATION_SUCCESS -eq 0 ]; then
  test_success "Automated rotation script executed successfully"
  
  # Verify authentication after rotation
  LATEST_SECRET=$(curl -s -X GET \
    "${VAULT_ADDR}/v1/kv/data/keycloak/clients/${REALM}/${CLIENT_ID}" \
    -H "X-Vault-Token: ${VAULT_TOKEN}" | \
    jq -r '.data.data.client_secret')
  
  AUTH_TEST=$(curl -s -X POST \
    "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=client_credentials" \
    -d "client_id=${CLIENT_ID}" \
    -d "client_secret=${LATEST_SECRET}" \
    -d "scope=openid")
  
  if echo "$AUTH_TEST" | jq -e '.access_token' > /dev/null; then
    test_success "Authentication successful with latest rotated secret"
  else
    test_failure "Authentication failed with latest rotated secret" "Response: $AUTH_TEST"
  fi
else
  test_failure "Automated rotation script failed" "Exit code: $ROTATION_SUCCESS, Output: $ROTATION_OUTPUT"
fi

echo -e "\n=========================================================="
echo -e "                 TEST RESULTS SUMMARY                     "
echo -e "=========================================================="

if [ $TEST_FAILURES -eq 0 ]; then
  echo -e "${GREEN}All tests passed successfully!${NC}"
else
  echo -e "${RED}$TEST_FAILURES test(s) failed.${NC}"
fi

echo -e "\n${YELLOW}Note: Some tests may require manual verification in a browser${NC}"
echo "See test details above for specific issues and required manual steps."
echo "=========================================================="

exit $TEST_FAILURES 