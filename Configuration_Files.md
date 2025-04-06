# Client Secret Rotation Components

This document outlines all the components needed for the automated client secret rotation between Keycloak and HashiCorp Vault.

## Source Code and Configuration Files

### 1. Docker Compose Configuration
- **`docker-compose.yml`** - Defines and orchestrates Keycloak, Vault, and the client secret rotation container.
  - Location: Root directory
  - Purpose: Sets up all services, environment variables, volumes, and networking

### 2. Vault Configuration Files
- **`vault/config.hcl`** - Vault server configuration
  - Location: `vault/config.hcl`
  - Purpose: Configures Vault storage, listener, and UI settings
  
- **`vault/keycloak-policy.hcl`** - Vault policy restricting Keycloak's key access
  - Location: `vault/keycloak-policy.hcl`
  - Purpose: Defines access policies for Keycloak to secret paths

### 3. Keycloak Realm Configuration
- **`realm-export.json`** - Pre-configured Keycloak realm using Vault for key retrieval
  - Location: Root directory
  - Purpose: Provides a ready-to-import realm configuration with Vault integration

### 4. Client Secret Rotation Scripts
- **`scripts/auto-initialize.sh`** - Main initialization script
  - Location: `scripts/auto-initialize.sh`
  - Purpose: Orchestrates the setup of all components

- **`scripts/create-fresh-realm.sh`** - Creates realm and client in Keycloak
  - Location: `scripts/create-fresh-realm.sh`
  - Purpose: Sets up the Keycloak realm and client configuration

- **`scripts/setup-vault-integration-fresh.sh`** - Sets up Vault integration
  - Location: `scripts/setup-vault-integration-fresh.sh`
  - Purpose: Configures Vault to store client secrets for Keycloak

- **`scripts/rotate-client-secret.sh`** - Rotates client secrets
  - Location: `scripts/rotate-client-secret.sh`
  - Purpose: Main script for client secret rotation
  
- **`scripts/clear-keycloak-sessions.sh`** - Clears Keycloak sessions
  - Location: `scripts/clear-keycloak-sessions.sh`
  - Purpose: Clears sessions when secrets are rotated

- **`scripts/init-vault.sh`** - Initializes Vault
  - Location: `scripts/init-vault.sh`
  - Purpose: Sets up Vault for client secret storage

### 5. Demo Application
- **`client-app/`** - Flask application demonstrating the integration
  - Location: `client-app/`
  - Purpose: Shows how a client application can retrieve secrets from Vault

## How Client Secret Rotation Works

1. **Initial Setup**:
   - The `auto-initialize.sh` script orchestrates the setup of Keycloak and Vault
   - A realm and client are created in Keycloak
   - The client secret is stored in Vault

2. **Rotation Process**:
   - The `rotate-client-secret.sh` script:
     - Gets the current client secret from Keycloak and Vault
     - Verifies they match
     - Generates a new client secret in Keycloak
     - Stores the new secret in Vault
     - Tests authentication with the new secret
     - Verifies the old secret no longer works

3. **Automation**:
   - A cron job runs daily to rotate the client secret
   - The client application retrieves the latest secret from Vault before authentication

4. **Security**:
   - Sessions are cleared after secret rotation
   - Applications always get the latest secret from Vault
   - Failed rotations are logged and can be monitored

## Manual Operations

### Import Realm Configuration
```bash
docker exec keycloak /opt/keycloak/bin/kc.sh import --file /tmp/realm-export.json
```

### Manual Client Secret Rotation
```bash
docker exec client-secret-rotation /scripts/rotate-client-secret.sh
```

### Clear Keycloak Sessions
```bash
docker exec client-secret-rotation /scripts/clear-keycloak-sessions.sh
```

### View Rotation Logs
```bash
docker exec client-secret-rotation cat /var/log/cron.log
``` 