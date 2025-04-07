# Keycloak Client Secret Automation with HashiCorp Vault

This project demonstrates how to integrate HashiCorp Vault with Keycloak for automated client secret management. It includes scripts for:

1. Creating realms and clients in Keycloak
2. Storing client secrets in HashiCorp Vault
3. Rotating client secrets automatically
4. Testing authentication with client secrets from Vault
5. Demo Flask application showing integration in action

## Prerequisites

- Docker and Docker Compose
- Bash shell (for Linux/macOS) or Git Bash/WSL (for Windows)

## Quickstart

```bash
# Clone the repository
git clone https://github.com/AdityaPrakash2/AutoKeyRotation.git
cd AutoKeyRotation

# Create your environment file from the example
cp .env.example .env
# Edit the .env file to set secure passwords for production
nano .env  # or use your preferred editor

# Start all services in the background
# Please allow 30-60 seconds after running this command to ensure all components are fully setup!
docker-compose up -d

# Check running containers
docker ps

# View logs
docker-compose logs -f

# View logs for a specific service
docker-compose logs -f keycloak
docker-compose logs -f vault
docker-compose logs -f flask-app
docker-compose logs -f client-secret-rotation

# Stop all services
docker-compose down
```

## Components

The project consists of several components that work together:

1. **Keycloak** - Identity and access management server
2. **HashiCorp Vault** - Secret management server
3. **Client Secret Rotation Service** - Alpine-based container that manages client secret rotation
4. **Flask Demo App** - Web application that demonstrates the integration
5. **PostgreSQL** - Database for Keycloak

## Accessing the Applications

### Demo Flask Application
- **URL**: http://localhost:5001/
- **Features**:
  - Login with Keycloak credentials:
    - Username: `test-user`
    - Password: `password`
  - System Status Check (only visible after login)
  - Direct Token Retrieval (only visible after login)
  - Proper logout functionality

### Keycloak Admin Console
- **URL**: http://localhost:8080/admin/
- **Admin Credentials**:
  - Username: `admin`
  - Password: `admin`
- **Key areas to explore**:
  - Realms > fresh-realm > Clients > fresh-client
  - Client settings and credentials

### HashiCorp Vault UI
- **URL**: http://localhost:8201/ui/
- **Root Token**: `root`
- **Key areas to explore**:
  - Secrets > kv > keycloak > clients > fresh-realm > fresh-client
  - Secret version history shows the rotation history

## Project Structure

```
.
├── docker-compose.yml    # Docker services configuration
├── README.md             # This documentation
├── ROADMAP.md            # Future development plans
├── client-app/           # Demo Flask application
│   ├── app.py            # Flask application code
│   ├── Dockerfile        # Flask app container definition
│   ├── requirements.txt  # Python dependencies
│   └── templates/        # HTML templates for the web UI
├── scripts/              # Core automation scripts
│   ├── auto-initialize.sh            # Main initialization script
│   ├── cleanup-realms.sh             # Cleans up unnecessary realms
│   ├── create-fresh-realm.sh         # Creates realm and client in Keycloak
│   ├── cron-rotate-client-secret.sh  # Called by cron for rotation
│   ├── init-vault.sh                 # Initializes Vault
│   ├── rotate-client-secret.sh       # Rotates client secrets
│   ├── setup-vault-integration-fresh.sh  # Sets up Vault integration
│   └── update-client-for-webapp.sh   # Updates client for web application
└── vault/                # Vault configuration files
```

## How It Works

### Client Secret Rotation

1. The rotation process:
   - Retrieves the current client secret from both Keycloak and Vault
   - Verifies they match to ensure consistency
   - Generates a new client secret
   - Updates the client secret in Keycloak
   - Stores the new secret in Vault
   - Tests authentication with the new secret
   - Verifies the old secret no longer works

2. Automation:
   - A cron job runs daily at 2 AM to rotate client secrets
   - Logs are stored in the client_rotation_logs volume
   - Secrets are rotated without disrupting client applications (they retrieve the latest secrets from Vault)

### Flask Application Architecture

1. The Flask app demonstrates proper integration:
   - Retrieves the client secret from Vault before authenticating
   - Uses separate URLs for internal communication vs. browser redirects
   - Properly handles login and logout flows with Keycloak
   - Demonstrates extracting user info from JWT tokens
   - Implements session cleanup during shutdown

2. Security features:
   - API endpoints are protected and require authentication
   - Only authenticated users can see system status and token options
   - Proper session management with cleanup

## Manual Client Secret Rotation

To manually rotate the client secret:

```bash
docker exec client-secret-rotation /scripts/rotate-client-secret.sh
```

## Clearing Keycloak Sessions

To manually clear all Keycloak sessions:

```bash
docker exec client-secret-rotation /scripts/clear-keycloak-sessions.sh
```

## Troubleshooting

### Authentication Issues

If you encounter "invalid_client" errors:

1. Check the Keycloak logs: `docker-compose logs keycloak`
2. Verify that the client secrets match between Keycloak and Vault
3. Make sure the client is correctly configured in Keycloak (non-public, client credentials enabled)
4. Try clearing all sessions: `docker exec client-secret-rotation /scripts/clear-keycloak-sessions.sh`
5. Restart the environment: `docker-compose restart`

### Session Persistence Issues

If you're still logged in after restarting containers with `docker-compose down` and `docker-compose up`:

1. Flask sessions are stored in browser cookies, and Keycloak sessions may persist in the database
2. To completely clear all sessions, run:
   ```bash
   docker exec client-secret-rotation /scripts/clear-keycloak-sessions.sh
   ```
3. Additionally, clear your browser cookies for the application domain
4. Each restart of the Flask app generates a new secret key, which should invalidate existing sessions

### Vault Integration Issues

If Vault integration is not working:

1. Check Vault's accessibility: `curl http://localhost:8201/v1/sys/health`
2. Verify the Vault token has the correct permissions
3. Ensure the secret path is correct
4. Check that the KV secrets engine is enabled in Vault

### Flask App Issues

If the Flask demo app is not working properly:

1. Check the logs: `docker-compose logs flask-app`
2. Try logging out and clearing sessions: `docker exec client-secret-rotation /scripts/clear-keycloak-sessions.sh`
3. Verify the environment variables in the Docker Compose file

## Windows Compatibility

If you're running this project on Windows, you might encounter issues with shell script line endings. Windows uses CRLF line endings, but the scripts need to use LF line endings to run correctly in Docker containers.

### Using the Helper Script

A helper batch file is provided to convert scripts to the correct format:

1. Install `dos2unix` via Git Bash, WSL, or Chocolatey
2. Run the `prepare-scripts-for-windows.bat` file
3. Restart your containers if they were already running

### Manual Conversion

Alternatively, you can manually convert the scripts:

```bash
# Using Git Bash or WSL
find ./scripts -type f -name "*.sh" -exec dos2unix {} \;
```

### Git Configuration

The repository includes a `.gitattributes` file that helps manage line endings correctly. If you're cloning the repository, Git should handle line endings automatically.

## Security Considerations

- This demo uses the Vault root token and Keycloak admin credentials for simplicity
- In production:
  - Use proper access controls and policies in Vault
  - Rotate Vault tokens regularly
  - Use TLS for all connections between components
  
## Environment Variables

This project uses environment variables for configuration to avoid hardcoding sensitive information. The main configuration is loaded from the `.env` file, which is not included in version control for security reasons.

### Setup

1. Copy the example configuration: `cp .env.example .env`
2. Edit the `.env` file to set appropriate values for your environment
3. For production deployments, ensure you use strong, unique passwords

### Important Variables

- **Database Configuration**: Controls PostgreSQL database access
- **Keycloak Configuration**: Sets admin credentials and database access
- **Vault Configuration**: Configures Vault tokens and access
- **Flask App Configuration**: Controls the demo application settings

In production environments, consider using a secrets management solution like HashiCorp Vault or AWS Secrets Manager to handle these variables rather than an `.env` file.

