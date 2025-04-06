# Keycloak Client Secret Automation with HashiCorp Vault

This project demonstrates how to integrate HashiCorp Vault with Keycloak for automated client secret management. It includes scripts for:

1. Creating realms and clients in Keycloak
2. Storing client secrets in HashiCorp Vault
3. Rotating client secrets automatically
4. Testing authentication with client secrets from Vault

## Prerequisites

- Docker and Docker Compose
- Bash shell (for Linux/macOS) or Git Bash/WSL (for Windows)

## Quickstart

### Option 1: Simple Docker Compose Command

```bash
docker-compose up -d
```

This single command will:
1. Start all services (Keycloak, Vault, PostgreSQL)
2. Run the initialization script automatically
3. Create the realm and client in Keycloak
4. Configure Vault integration and rotation

Everything will run in the background. To check progress, you can view the logs:

```bash
docker logs -f client-secret-rotation
```

### Option 2: Interactive Startup

For a more interactive experience with visible logs:

```bash
./start.sh
```

This script will start all services and show the logs during initialization.

## Project Structure

This project has been streamlined to include only the necessary components:

```
.
├── docker-compose.yml    # Docker services configuration
├── README.md             # This documentation
├── ROADMAP.md            # Future development plans
├── scripts/              # Core automation scripts
│   ├── auto-initialize.sh            # Main initialization script
│   ├── create-fresh-realm.sh         # Creates realm and client in Keycloak
│   ├── cron-rotate-client-secret.sh  # Called by cron for rotation
│   ├── init-vault.sh                 # Initializes Vault (if needed)
│   ├── rotate-client-secret.sh       # Rotates client secrets
│   └── setup-vault-integration-fresh.sh  # Sets up Vault integration
├── start.sh              # Convenience script to start everything
└── vault/                # Vault configuration (if needed)
```

The project has been streamlined to include only the essential scripts needed for core functionality, with all development and test scripts removed.

## Verification

### Access Keycloak Admin Console

- URL: http://localhost:8080/
- Username: `admin`
- Password: `admin`

Navigate to the "fresh-realm" and check the "fresh-client" configuration.

### Access Vault UI

- URL: http://localhost:8201/ui
- Token: `root`

Navigate to "Secret > kv > data > keycloak > clients > fresh-realm > fresh-client" to see the stored client secret.

## Client Applications

Client applications should retrieve the client secret from Vault instead of hardcoding it. Here's a simple example in Python:

```python
import hvac
import requests

# Vault client configuration
vault_client = hvac.Client(url='http://vault:8201', token='root')

# Retrieve client secret from Vault
secret_path = 'kv/data/keycloak/clients/fresh-realm/fresh-client'
secret_response = vault_client.secrets.kv.v2.read_secret_version(path=secret_path)
client_secret = secret_response['data']['data']['client_secret']

# Use the secret for authentication with Keycloak
auth_response = requests.post(
    'http://keycloak:8080/realms/fresh-realm/protocol/openid-connect/token',
    data={
        'client_id': 'fresh-client',
        'client_secret': client_secret,
        'grant_type': 'client_credentials'
    },
    headers={'Content-Type': 'application/x-www-form-urlencoded'}
)

# Use the access token
if auth_response.status_code == 200:
    access_token = auth_response.json()['access_token']
    # Use the access token for API calls
    print(f"Got access token: {access_token[:10]}...")
else:
    print(f"Authentication failed: {auth_response.text}")
```

## Automated Rotation

The client secret is automatically rotated daily at 2 AM by a cron job in the client-secret-rotation container. 

Logs for the rotation are stored in:
- `/var/log/keycloak-rotation/client-secret-rotation-YYYY-MM-DD.log` inside the container
- The mounted volume `client_rotation_logs` on your host

## Troubleshooting

### Authentication Issues

If you encounter "invalid_client" errors:

1. Check the Keycloak logs: `docker logs keycloak`
2. Verify that the client secrets match between Keycloak and Vault
3. Make sure the client is correctly configured in Keycloak (non-public, client credentials enabled)
4. Restart the environment: `docker-compose down && ./start.sh`

### Vault Integration Issues

If Vault integration is not working:

1. Check Vault's accessibility: `curl http://localhost:8201/v1/sys/health`
2. Verify the Vault token has the correct permissions
3. Ensure the secret path is correct
4. Check that the KV secrets engine is enabled in Vault

## Stopping the Environment

To stop all services:

```bash
docker-compose down
```

To stop and remove all data (clean start):

```bash
docker-compose down -v
```

## Security Considerations

- Use proper access controls and policies in Vault to restrict access to client secrets
- Rotate Vault tokens regularly
- Use TLS for all connections between components in production
- Store sensitive configuration values in environment variables, not hardcoded in scripts
- Implement proper error handling and alerting for failed rotations 