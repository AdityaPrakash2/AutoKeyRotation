#!/bin/bash

# Configuration
VAULT_ADDR=${VAULT_ADDR:-"http://vault:8201"}
VAULT_TOKEN=${VAULT_TOKEN:-"root"}
KEY_PATH="secret/data/keycloak/keys/signing"

# Set Vault address and token
export VAULT_ADDR
export VAULT_TOKEN

echo "Retrieving active key from Vault..."

# Get the keys data from Vault
VAULT_DATA=$(curl -s -H "X-Vault-Token: ${VAULT_TOKEN}" \
  "${VAULT_ADDR}/v1/${KEY_PATH}" | jq -r '.data.data')

# Extract active key ID
ACTIVE_KEY_ID=$(echo "${VAULT_DATA}" | jq -r '.active')

# Get the active key details
ACTIVE_KEY=$(echo "${VAULT_DATA}" | jq -r ".keys[\"${ACTIVE_KEY_ID}\"]")

echo "Active key ID: ${ACTIVE_KEY_ID}"
echo "Active key creation timestamp: $(echo "${ACTIVE_KEY}" | jq -r '.created')"
echo "Active key algorithm: $(echo "${ACTIVE_KEY}" | jq -r '.algorithm')"

# Show public key only (for security)
PUBLIC_KEY=$(echo "${ACTIVE_KEY}" | jq -r '.publicKey')
echo "Public Key: ${PUBLIC_KEY}"

echo "To see full key details, including private key, access Vault UI at ${VAULT_ADDR}/ui" 