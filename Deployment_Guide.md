# Deployment Guide for Client Secret Rotation

This guide provides step-by-step instructions for setting up the client secret rotation solution with Keycloak and HashiCorp Vault.

## Prerequisites

- Docker and Docker Compose installed
- Git (to clone the repository)
- Basic understanding of Keycloak and Vault concepts

## 1. Initial Setup

### Clone the Repository

```bash
git clone https://github.com/yourusername/AutoKeyRotation.git
cd AutoKeyRotation
```

### Start the Environment

```bash
docker-compose up -d
```

This command will:
- Start PostgreSQL for Keycloak's database
- Start Keycloak on port 8080
- Start Vault on port 8201
- Start the client-secret-rotation container that handles automation
- Start the Flask demo application on port 5001

## 2. Setting Up and Initializing Vault

The client-secret-rotation container automatically initializes Vault, but you can verify or manually set up as follows:

### Verify Vault is Running

```bash
curl http://localhost:8201/v1/sys/health | jq
```

You should see Vault's health status with `"initialized": true`.

### Manual Vault Initialization (if needed)

If you need to manually initialize Vault:

```bash
# Access the Vault container
docker exec -it vault sh

# Initialize Vault with the root token
export VAULT_ADDR='http://127.0.0.1:8201'
vault operator init -key-shares=1 -key-threshold=1

# Unseal Vault (replace with the key from the previous command)
vault operator unseal KEY

# Authenticate with the root token
vault login ROOT_TOKEN

# Enable the KV secrets engine
vault secrets enable -path=kv kv-v2

# Create a policy for Keycloak
cat << EOF > keycloak-policy.hcl
path "kv/data/keycloak/clients/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "kv/metadata/keycloak/clients/*" {
  capabilities = ["read", "list"]
}
EOF

vault policy write keycloak-policy keycloak-policy.hcl

# Exit the container
exit
```

### Verify Vault Configuration

```bash
# Check that the KV secrets engine is enabled
docker exec vault vault secrets list

# Check policies
docker exec vault vault policy list
docker exec vault vault policy read keycloak-policy
```

## 3. Importing and Configuring Keycloak Realms

The auto-initialization process creates the realm automatically, but you can also manually import the realm:

### Copy the Realm Export to Keycloak

```bash
docker cp realm-export.json keycloak:/tmp/realm-export.json
```

### Import the Realm

```bash
docker exec keycloak /opt/keycloak/bin/kc.sh import --file /tmp/realm-export.json
```

### Manual Realm and Client Creation (if needed)

If you need to manually create the realm and client:

```bash
# Use the script to create a fresh realm and client
docker exec client-secret-rotation /scripts/create-fresh-realm.sh
```

### Set Up Vault Integration

```bash
# Use the script to set up Vault integration
docker exec client-secret-rotation /scripts/setup-vault-integration-fresh.sh
```

## 4. Verifying Keycloak and Vault Integration

### Check Client Secret in Vault

```bash
docker exec vault vault kv get kv/keycloak/clients/fresh-realm/fresh-client
```

You should see the client secret stored in Vault.

### Test Authentication Using the Secret from Vault

```bash
# Get the client secret from Vault
CLIENT_SECRET=$(docker exec vault vault kv get -format=json kv/keycloak/clients/fresh-realm/fresh-client | jq -r '.data.data.client_secret')

# Test authentication with the secret
curl -X POST \
  "http://localhost:8080/realms/fresh-realm/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=fresh-client" \
  -d "client_secret=$CLIENT_SECRET"
```

If successful, you'll receive an access token in the response.

### Verify Through the Demo Application

1. Open a browser and navigate to http://localhost:5001
2. Click on "Login with Keycloak"
3. Log in with the test user credentials (username: `test-user`, password: `password`)
4. If successful, you'll be redirected back to the application showing your user info

## 5. Manually Triggering Client Secret Rotation

### Rotate the Client Secret

```bash
docker exec client-secret-rotation /scripts/rotate-client-secret.sh
```

This command will:
1. Get the current client secret from Keycloak and Vault
2. Verify they match
3. Generate a new client secret in Keycloak
4. Store the new secret in Vault
5. Test authentication with the new secret
6. Verify the old secret no longer works

### Verify the New Secret in Vault

```bash
docker exec vault vault kv get kv/keycloak/clients/fresh-realm/fresh-client
```

You'll see the new client secret is different from the previous one.

### Verify Authentication Still Works

```bash
# Get the new client secret from Vault
NEW_CLIENT_SECRET=$(docker exec vault vault kv get -format=json kv/keycloak/clients/fresh-realm/fresh-client | jq -r '.data.data.client_secret')

# Test authentication with the new secret
curl -X POST \
  "http://localhost:8080/realms/fresh-realm/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=fresh-client" \
  -d "client_secret=$NEW_CLIENT_SECRET"
```

You should still receive a valid access token.

## 6. Monitoring and Troubleshooting

### View Rotation Logs

```bash
docker exec client-secret-rotation cat /var/log/cron.log
```

### View Keycloak Logs

```bash
docker logs keycloak
```

### View Vault Audit Logs (if enabled)

```bash
docker exec vault vault audit list
```

### Clear Keycloak Sessions

If you encounter any authentication issues after rotation:

```bash
docker exec client-secret-rotation /scripts/clear-keycloak-sessions.sh
```

## 7. Testing and Validation

A comprehensive testing script is included to verify all aspects of the client secret rotation:

```bash
# Run the testing suite
docker exec client-secret-rotation /scripts/test-client-secret-rotation.sh
```

### What the Tests Verify

#### Functional Tests
- Validates that Keycloak can connect to Vault
- Verifies that Keycloak is retrieving the correct client secret from Vault
- Ensures JWTs issued by Keycloak are valid and properly signed
- Validates token claims (issuer, audience, expiration)

#### Security Tests
- Validates that old client secrets are no longer usable after rotation
- Confirms that Vault enforces access control policies
- Verifies proper storage and retrieval of secrets

#### Integration Tests
- Simulates client secret rotation and verifies seamless transition
- Ensures authentication continues to work after rotation
- Tests the complete rotation workflow
- Validates that client applications can retrieve the latest secrets

### Manual Testing Steps

Some aspects require manual verification:

1. **User Authentication Flow**: 
   - The test will provide a URL to test in your browser
   - Log in with the provided test user credentials
   - Verify successful authentication and redirection

2. **Client Application Integration**:
   - The Flask demo application at http://localhost:5001 demonstrates integration
   - It retrieves the client secret from Vault on-demand
   - Try logging in before and after rotation to verify continuity

## 8. Stopping the Environment

```bash
docker-compose down
```

To remove all data and start fresh:

```bash
docker-compose down -v
```

## Next Steps

- Configure secure production settings for Vault and Keycloak
- Set up monitoring for the rotation process
- Implement backup procedures for Vault data
- Consider implementing a high availability setup for production