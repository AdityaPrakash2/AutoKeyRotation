#!/bin/bash
set -e

# Configuration
VAULT_ADDR=${VAULT_ADDR:-"http://localhost:8201"}
VAULT_TOKEN=${VAULT_TOKEN:-"root"}

echo "Initializing Vault for Keycloak integration..."

# Enable the KV v2 secrets engine if not already enabled
echo "Enabling KV secrets engine..."
curl -s \
  -H "X-Vault-Token: $VAULT_TOKEN" \
  -X POST \
  -d '{"type": "kv", "options": {"version": "2"}}' \
  $VAULT_ADDR/v1/sys/mounts/secret || echo "Secret engine may already be enabled"

# Create Keycloak policy
echo "Creating Keycloak policy..."
curl -s \
  -H "X-Vault-Token: $VAULT_TOKEN" \
  -X PUT \
  -d '{
    "policy": "path \"secret/data/keycloak/keys/*\" {\n  capabilities = [\"read\", \"list\"]\n}\n\npath \"secret/metadata/keycloak/keys/*\" {\n  capabilities = [\"read\", \"list\"]\n}"
  }' \
  $VAULT_ADDR/v1/sys/policies/acl/keycloak

# Create a token with the Keycloak policy
echo "Creating Keycloak token..."
KEYCLOAK_TOKEN=$(curl -s \
  -H "X-Vault-Token: $VAULT_TOKEN" \
  -X POST \
  -d '{
    "policies": ["keycloak"],
    "ttl": "720h",
    "renewable": true
  }' \
  $VAULT_ADDR/v1/auth/token/create | grep -o '"client_token":"[^"]*' | cut -d':' -f2 | tr -d '"')

echo "Vault initialization completed!"
echo "Keycloak token: $KEYCLOAK_TOKEN"
echo ""
echo "Save this token. You will need it for Keycloak configuration."
echo "You can now generate an initial key by running ./scripts/rotate-keys-with-history.sh" 