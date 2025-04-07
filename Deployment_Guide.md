# Deployment Guide for Client Secret Rotation

This guide provides step-by-step instructions for setting up the client secret rotation solution with Keycloak and HashiCorp Vault.

## Prerequisites

- Docker and Docker Compose installed
- Git (to clone the repository)
- Basic understanding of Keycloak and Vault concepts

## 1. Initial Setup

### Clone the Repository

```bash
git clone https://github.com/AdityaPrakash2/AutoKeyRotation.git
cd AutoKeyRotation
```

### Set Up Environment File

```bash
# Create your environment file from the example
cp .env.example .env

# Edit the .env file to set secure passwords for production
nano .env  # or use your preferred editor
```

Note: For development purposes, you can use simpler passwords, but make sure to use strong, unique passwords in production.

### Start the Environment

```bash
docker-compose up -d
```
# Please allow 60-120 seconds after running this command to ensure all components are fully setup!

This command will start all required services:
- PostgreSQL for Keycloak
- Keycloak on port 8080
- Vault on port 8201
- Client secret rotation container
- Flask demo application on port 5001

### Accessing Keycloak and Vault

#### Keycloak Admin Console
- URL: http://localhost:8080/admin/
- Admin credentials:
  - Username: The value of `KEYCLOAK_ADMIN` from your .env file (default: `admin`)
  - Password: The value of `KEYCLOAK_ADMIN_PASSWORD` from your .env file (default: `change_me_in_production`)
- After login, you can:
  - Manage realms, clients, and users
  - Configure authentication flows
  - View and manage client secrets

#### Vault UI
- URL: http://localhost:8201/ui/
- Root token: The value of `VAULT_DEV_ROOT_TOKEN_ID` from your .env file (default: `change_me_in_production`)
- After login, you can:
  - View and manage secrets
  - Configure policies
  - Monitor audit logs

## 2. Setting Up Vault

The client-secret-rotation container automatically initializes Vault. You can verify it's running with:

```bash
curl http://localhost:8201/v1/sys/health | jq
```

## 3. Keycloak Setup

The auto-initialization process creates the realm automatically. You can verify the setup by:

1. Opening http://localhost:5001 in your browser
2. Clicking "Login with Keycloak"
3. Logging in with test credentials (username: `test-user`, password: `password`)

## 4. Testing Client Secret Rotation

### Trigger Rotation

```bash
docker exec client-secret-rotation /scripts/rotate-client-secret.sh
```

### Verify Rotation

1. Check the new secret in Vault:
```bash
docker exec vault vault kv get kv/keycloak/clients/fresh-realm/fresh-client
```

2. Test authentication with the new secret:
```bash
curl -X POST \
  "http://localhost:8080/realms/fresh-realm/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=fresh-client" \
  -d "client_secret=$NEW_CLIENT_SECRET"
```

## 5. Stopping the Environment

```bash
docker-compose down
```

To remove all data and start fresh:
```bash
docker-compose down -v
```