#!/bin/bash
set -e

echo "Restarting Auto Key Rotation with Keycloak and Vault"
echo "==================================================="
echo ""

# Make sure scripts are executable
echo "Setting up permissions..."
chmod +x scripts/*.sh
if [ -f keycloak-vault-spi/deploy.sh ]; then
    chmod +x keycloak-vault-spi/deploy.sh
fi

# Check if we should prepare the SPI
if [ -d keycloak-vault-spi ] && [ ! -f keycloak-vault-spi/deploy/keycloak-vault-spi-1.0.0-SNAPSHOT.jar ]; then
    echo "SPI source code found but no built JAR."
    echo "Would you like to build the SPI? (y/n)"
    read -r build_spi
    
    if [[ "$build_spi" =~ ^[Yy]$ ]]; then
        echo "Building SPI..."
        cd keycloak-vault-spi
        ./deploy.sh
        cd ..
    else
        echo "Skipping SPI build. Using placeholder JAR."
        mkdir -p keycloak-vault-spi/deploy
        echo "placeholder" > keycloak-vault-spi/deploy/keycloak-vault-spi-1.0.0-SNAPSHOT.jar
    fi
fi

# Export Vault token from environment or generate a random one
if [ -z "$VAULT_TOKEN" ]; then
    export VAULT_TOKEN="root"
    echo "Using default Vault token: 'root'"
else
    echo "Using provided Vault token from environment"
fi

# Stop all services
echo "Stopping all services..."
docker-compose down

# Clean up all volumes for a completely fresh start
echo "Cleaning up ALL data for completely fresh start..."
docker-compose down -v
docker volume rm -f autokeyrotation_postgres_data autokeyrotation_vault_data 2>/dev/null || true

# Start the services with clean state
echo "Starting services with docker-compose..."
docker-compose up -d

echo ""
echo "Services are starting up. This may take a minute."
echo "The key-rotation service will:"
echo "1. Initialize Vault with required configuration"
echo "2. Generate initial keys"
echo "3. Create a dedicated 'vault-integrated' realm"
echo "4. Set up key providers to display keys"
echo "5. Start the automatic key rotation service"
echo ""
echo "Access the services at:"
echo "- Keycloak Admin Console: http://localhost:8080/"
echo "  - Username: admin"
echo "  - Password: admin"
echo "- Vault UI: http://localhost:8201/ui"
echo "  - Token: root"
echo ""
echo "To see the custom realm with the Vault keys:"
echo "1. Log in to Keycloak Admin Console (http://localhost:8080/)"
echo "2. Go to the dropdown in the top-left corner (currently showing 'master')"
echo "3. Select 'vault-integrated' realm"
echo "4. Go to Realm Settings"
echo "5. Click on the 'Keys' tab"
echo "6. You should see 'vault-key-provider' and 'fallback-key-provider'"
echo ""
echo "To view logs:"
echo "docker-compose logs -f"
echo ""
echo "To check the active key in Vault:"
echo "docker exec -it key-rotation /scripts/show-active-key.sh"
echo ""
echo "To manually rotate keys:"
echo "docker exec -it key-rotation /scripts/rotate-keys-with-history.sh" 