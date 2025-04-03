#!/bin/bash
set -e

# Configuration
VAULT_ADDR=${VAULT_ADDR:-"http://vault:8201"}
VAULT_TOKEN=${VAULT_TOKEN:-"root"}
KEY_PATH="secret/data/keycloak/keys/signing"

# Get current keys from Vault
echo "Retrieving current keys from Vault..."
CURRENT_KEYS=$(curl -s \
  -H "X-Vault-Token: $VAULT_TOKEN" \
  $VAULT_ADDR/v1/$KEY_PATH)

# Check if we have keys already
if echo "$CURRENT_KEYS" | grep -q "errors"; then
  # No keys exist yet, start with empty set
  KEYS_JSON="{}"
else
  # Extract existing keys
  KEYS_JSON=$(echo "$CURRENT_KEYS" | jq -r '.data.data.keys // {}')
fi

# Generate new RSA key pair with improved randomness
echo "Generating new RSA key pair..."
# Create a unique random seed file
RANDOM_SEED="/tmp/random_seed_$(date +%s)_$RANDOM"
dd if=/dev/urandom of=$RANDOM_SEED bs=256 count=1 2>/dev/null
# Generate key with the random seed
PRIVATE_KEY=$(openssl genrsa -rand $RANDOM_SEED 2048 2>/dev/null)
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | openssl rsa -pubout 2>/dev/null)
# Clean up seed file
rm -f $RANDOM_SEED

# Format keys for JSON
PRIVATE_KEY_JSON=$(echo "$PRIVATE_KEY" | awk '{printf "%s\\n", $0}' | tr -d '\n')
PUBLIC_KEY_JSON=$(echo "$PUBLIC_KEY" | awk '{printf "%s\\n", $0}' | tr -d '\n')

# Generate a more Keycloak-friendly key ID (base64url encoded random string)
# Format: [a-zA-Z0-9_-]{22}
KEY_ID=$(openssl rand -base64 16 | tr '+/' '-_' | tr -d '=' | cut -c1-22)
echo "Generated key ID: $KEY_ID"

# Current timestamp for metadata
TIMESTAMP=$(date +%s)

# Prepare new key JSON
NEW_KEY_JSON=$(cat <<EOF
{
  "privateKey": "$PRIVATE_KEY_JSON",
  "publicKey": "$PUBLIC_KEY_JSON",
  "algorithm": "RS256",
  "created": $TIMESTAMP
}
EOF
)

# Add new key to existing keys
UPDATED_KEYS=$(echo "$KEYS_JSON" | jq --arg kid "$KEY_ID" --argjson keydata "$NEW_KEY_JSON" '. + {($kid): $keydata}')

# Create final JSON payload
JSON_PAYLOAD=$(cat <<EOF
{
  "data": {
    "active": "$KEY_ID",
    "keys": $UPDATED_KEYS
  }
}
EOF
)

# Store in Vault
echo "Storing updated keys in Vault..."
VAULT_RESPONSE=$(curl -s \
  -H "X-Vault-Token: $VAULT_TOKEN" \
  -H "Content-Type: application/json" \
  -X POST \
  -d "$JSON_PAYLOAD" \
  $VAULT_ADDR/v1/$KEY_PATH)

echo "Key rotation completed successfully!"
echo "New active key ID: $KEY_ID"
echo "Total keys in store: $(echo "$UPDATED_KEYS" | jq 'length')"

# Notify Keycloak about the key rotation
echo "Notifying Keycloak about key rotation..."
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
if [ -f "${SCRIPT_DIR}/notify-keycloak.sh" ]; then
  bash "${SCRIPT_DIR}/notify-keycloak.sh"
else
  echo "Warning: notify-keycloak.sh script not found."
fi

# Update the Keycloak provider with the new key
echo "Updating Keycloak provider with the new key..."
if [ -f "${SCRIPT_DIR}/setup-keycloak-provider.sh" ]; then
  bash "${SCRIPT_DIR}/setup-keycloak-provider.sh"
else
  echo "Warning: setup-keycloak-provider.sh script not found."
fi

# Display the active key details
if [ -f "${SCRIPT_DIR}/show-active-key.sh" ]; then
  bash "${SCRIPT_DIR}/show-active-key.sh"
else
  echo "Warning: show-active-key.sh script not found."
fi 