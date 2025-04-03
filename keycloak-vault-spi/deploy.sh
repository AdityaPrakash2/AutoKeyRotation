#!/bin/bash
set -e

echo "Building Keycloak Vault SPI..."
mvn clean package

echo "Creating deployment directory..."
DEPLOY_DIR="deploy"
mkdir -p $DEPLOY_DIR

echo "Copying JAR to deployment directory..."
cp target/keycloak-vault-spi-*.jar $DEPLOY_DIR/

echo "Creating Dockerfile for custom Keycloak image..."
cat > $DEPLOY_DIR/Dockerfile << EOF
FROM quay.io/keycloak/keycloak:22.0.0

# Copy the SPI JAR to the providers directory
COPY keycloak-vault-spi-*.jar /opt/keycloak/providers/

# Set environment variables
ENV KC_METRICS_ENABLED=true
ENV KC_HEALTH_ENABLED=true

# Build the optimized Keycloak server with our custom provider
RUN /opt/keycloak/bin/kc.sh build

# Expose the admin console port
EXPOSE 8080

# Start Keycloak in development mode 
ENTRYPOINT ["/opt/keycloak/bin/kc.sh", "start-dev"]
EOF

echo "The Keycloak Vault SPI has been built and prepared for deployment."
echo ""
echo "To build and run the custom Keycloak image with Vault integration:"
echo "  cd $DEPLOY_DIR"
echo "  docker build -t keycloak-vault:latest ."
echo "  docker run -p 8080:8080 -e KC_VAULT_URL=http://vault:8201 -e KC_VAULT_TOKEN=<your-token> -e KC_VAULT_KEY_PATH=secret/data/keycloak/keys/signing keycloak-vault:latest"
echo ""
echo "Or update your docker-compose.yml to use this custom image."

chmod +x $DEPLOY_DIR/Dockerfile 