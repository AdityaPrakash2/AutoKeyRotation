#!/bin/bash
set -e

# Configuration
VAULT_ADDR=${VAULT_ADDR:-http://vault:8201}
VAULT_TOKEN=${VAULT_TOKEN:-root}

echo "Initializing Vault at $VAULT_ADDR with token $VAULT_TOKEN"

# Enable KV secrets engine v2 at 'kv/' path
echo "Enabling KV secrets engine version 2 at path 'kv/'..."
curl -s -X POST \
  "$VAULT_ADDR/v1/sys/mounts/kv" \
  -H "X-Vault-Token: $VAULT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"type": "kv", "options": {"version": "2"}}' || echo "KV secrets engine may already be mounted"

# Disable unnecessary secret engines for a cleaner interface
# Note: cubbyhole engine cannot be disabled as it's used internally by Vault
echo "Disabling the default 'secret/' KV engine..."
curl -s -X DELETE \
  "$VAULT_ADDR/v1/sys/mounts/secret" \
  -H "X-Vault-Token: $VAULT_TOKEN" || echo "Secret engine might not exist or can't be disabled"

echo "Creating Keycloak secrets path..."
curl -s -X POST \
  "$VAULT_ADDR/v1/kv/data/keycloak/clients/fresh-realm/fresh-client" \
  -H "X-Vault-Token: $VAULT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"data":{"client_secret":"initial-secret"}}' > /dev/null

echo "Vault initialization completed successfully!" 