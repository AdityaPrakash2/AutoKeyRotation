# Automated Key Rotation in Keycloak Using HashiCorp Vault

This project implements automated key rotation for JWT signing in Keycloak, using HashiCorp Vault as a secure secret store.

## Current Status

- ✅ Working Docker Compose environment with Keycloak, Vault, PostgreSQL, and key rotation service
- ✅ Automated key generation and rotation scripts
- ✅ Integration between services
- ✅ Key history preservation
- ✅ Automatic key rotation notification to Keycloak
- ✅ Active key display and monitoring
- ✅ Custom realm with direct Vault key integration
- 🚧 Keycloak SPI for Vault integration (in progress)

## Getting Started

### Prerequisites

- Docker and Docker Compose installed
- Git (for cloning the repository)

### Setup Instructions

1. Clone this repository and navigate to its directory:
   ```
   git clone <repository-url>
   cd AutoKeyRotation
   ```

2. Start the services:
   ```
   ./restart.sh
   ```

3. The `restart.sh` script will:
   - Initialize Vault with the required configuration
   - Generate the initial signing key
   - Create a dedicated 'vault-integrated' realm
   - Set up key providers to display keys
   - Start the automatic key rotation service

4. Access the services:

   - **Keycloak Admin Console**: http://localhost:8080/
     - Username: `admin`
     - Password: `admin`

   - **HashiCorp Vault UI**: http://localhost:8201/ui
     - Token: `root` (this is the development root token)

### Verifying the Setup

1. Access the Vault UI and navigate to:
   - Secret → secret/keycloak/keys/signing
   
   You should see a JSON object containing your generated keys.

2. Access Keycloak and log in with admin credentials.

3. To see the custom realm with the Vault keys:
   - Go to the dropdown in the top-left corner (currently showing 'master')
   - Select 'vault-integrated' realm
   - Go to Realm Settings
   - Click on the 'Keys' tab
   - You should see 'vault-key-provider' and 'fallback-key-provider'

4. Verify the Keycloak environment variables:
   ```
   docker exec -it keycloak env | grep KC_VAULT
   ```
   You should see the configured Vault URL, token, and key path.

### Manual Key Rotation

You can manually trigger key rotation by running:
```
docker exec -it key-rotation /scripts/rotate-keys-with-history.sh
```

The script will:
1. Generate a new RSA key pair
2. Store it in Vault while preserving previous keys
3. Set the new key as active
4. Notify Keycloak to refresh its keys
5. Display information about the new active key

### Display Active Key

To display information about the currently active key:
```
docker exec -it key-rotation /scripts/show-active-key.sh
```

### Stopping the Services

To stop all services:
```
docker-compose down
```

To stop and remove volumes (will delete all data):
```
docker-compose down -v
```

## Project Components

1. **Keycloak**: An open-source Identity and Access Management solution
2. **HashiCorp Vault**: A secure secret management tool
3. **PostgreSQL**: Database for Keycloak
4. **Key Rotation Container**: Alpine-based container for key rotation scripts
   - `rotate-keys-with-history.sh`: Generates and rotates keys
   - `notify-keycloak.sh`: Notifies Keycloak about key rotations
   - `show-active-key.sh`: Displays information about the active key
   - `init-vault.sh`: Initializes Vault with required configuration
   - `create-custom-realm.sh`: Creates a custom realm with Vault key integration

## How It Works

1. The Vault container is initialized with a KV secrets engine
2. The key rotation service generates and manages RSA keys for Keycloak
3. Keys are stored securely in Vault with a versioning mechanism
4. A scheduler in the key-rotation service runs the rotation script hourly
5. The rotation script preserves old keys while making new ones active
6. When keys are rotated, a notification is sent to Keycloak to refresh its key cache
7. A custom realm is created with direct integration to the Vault keys
8. Keycloak is configured with environment variables to access Vault (SPI implementation in progress)

## Next Steps

Please refer to the ROADMAP.md file for detailed next steps, including:
- Completing the Keycloak SPI implementation for native Vault integration
- Enhancing security features
- Implementing monitoring and alerting
- Creating comprehensive documentation and deployment guides

## Troubleshooting

- **Vault Connection Issues**: Ensure that the Vault token is correct and has appropriate permissions
- **Key Rotation Failures**: Check key-rotation container logs with `docker logs key-rotation`
- **Keycloak Issues**: Check Keycloak logs with `docker logs keycloak`
- **Initialization Errors**: Make sure the init-vault.sh script completes successfully
- **Key Refresh Issues**: If Keycloak doesn't update its keys, check the notify-keycloak.sh script output 