FROM quay.io/keycloak/keycloak:22.0.0

# This is a placeholder for the custom provider JAR file
# In production, you would build the JAR and include it here
COPY keycloak-vault-spi-1.0.0-SNAPSHOT.jar /opt/keycloak/providers/

# Set environment variables
ENV KC_METRICS_ENABLED=true
ENV KC_HEALTH_ENABLED=true
ENV KC_SPI_KEYS_DEFAULT_PROVIDER=vault

# Build the optimized Keycloak server with our custom provider
RUN /opt/keycloak/bin/kc.sh build

# Expose the admin console port
EXPOSE 8080

# Start Keycloak in development mode 
ENTRYPOINT ["/opt/keycloak/bin/kc.sh", "start-dev"] 