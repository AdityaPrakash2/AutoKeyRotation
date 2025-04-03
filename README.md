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
   ```bash
   git clone <repository-url> # Replace with your repository URL
   cd AutoKeyRotation
   ```

2. Start the services using Docker Compose:
   ```bash
   docker-compose up -d
   ```
   This command will build the necessary images (if not already built) and start all services (Keycloak, Vault, PostgreSQL, key-rotation) in detached mode.

3. The `key-rotation` service automatically handles initialization on first start:
   - Waits for Vault and Keycloak to be available.
   - Initializes Vault with the required KV secrets engine (`secret/keycloak/keys/signing`).
   - Generates the initial signing key pair and stores it in Vault.
   - Creates the `vault-integrated` realm in Keycloak.
   - Configures the `vault-key-provider` (importing the key from Vault) and `fallback-key-provider` in the new realm.
   - Creates a test client (`test-client`) and user (`testuser`/`password`) in the `vault-integrated` realm.
   - Starts the hourly key rotation process.

4. Wait a minute or two for all services to fully initialize, especially the `key-rotation` service's setup steps.

5. Access the services:

   - **Keycloak Admin Console**: http://localhost:8080/
     - Username: `admin`
     - Password: `admin`

   - **HashiCorp Vault UI**: http://localhost:8201/ui
     - Token: `root` (this is the development root token)

### Optional: Using restart.sh

The `./restart.sh` script provides a convenient way to stop, remove volumes (perform a clean wipe), and restart the services. It also includes an optional (currently non-functional) step to build the Keycloak Vault SPI.

To perform a clean restart:
```bash
./restart.sh
```
Follow the prompts (you can usually answer 'n' to skip the SPI build).

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
   - You should see active keys listed. The `vault-key-provider` (using the key from Vault) and `fallback-key-provider` components are configured, although the imported Vault key might not be explicitly listed in the UI's 'Keys list' tab in Keycloak 22.

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

1. The `docker-compose up` command starts all containers.
2. The `key-rotation` container's entrypoint script waits for dependencies and then runs initialization scripts (`init-vault.sh`, `rotate-keys-with-history.sh`, `create-custom-realm.sh`, `setup-keycloak-provider.sh`).
3. `init-vault.sh` configures the KV secrets engine in Vault.
4. `rotate-keys-with-history.sh` generates the first key pair and saves it to Vault.
5. `create-custom-realm.sh` creates the `vault-integrated` realm and configures the `vault-key-provider` (importing the Vault key) and `fallback-key-provider`.
6. The `key-rotation` container then enters a loop, running `rotate-keys-with-history.sh` every hour.
7. `rotate-keys-with-history.sh` generates a new key, adds it to Vault, updates the active key pointer, and calls `notify-keycloak.sh`.
8. `notify-keycloak.sh` tells Keycloak to clear its key cache, forcing it to potentially reload keys (relevant if the SPI was working or if using a provider that reads dynamically).
9. The `vault-key-provider` component (using the built-in `rsa` provider) in Keycloak holds the imported key details.

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