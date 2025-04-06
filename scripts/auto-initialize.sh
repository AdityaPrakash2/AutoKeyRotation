#!/bin/bash
set -e

# Function for logging
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') [AUTO-INIT] $1"
}

log "Starting auto-initialization process..."

# Wait for Keycloak to be ready
log "Waiting for Keycloak to be ready..."
until curl -s -f -o /dev/null "http://keycloak:8080/realms/master"; do
  log "Keycloak not ready yet, waiting..."
  sleep 5
done
log "✅ Keycloak is ready!"

# Wait for Vault to be ready
log "Waiting for Vault to be ready..."
until curl -s -f -o /dev/null "http://vault:8201/v1/sys/health"; do
  log "Vault not ready yet, waiting..."
  sleep 5
done
log "✅ Vault is ready!"

# Initialize Vault to clean up default engines
log "Initializing Vault..."
/scripts/init-vault.sh || {
  log "⚠️ Vault initialization failed, but we'll continue"
}

# Clean up any unnecessary realms from previous runs
log "Cleaning up unnecessary realms..."
/scripts/cleanup-realms.sh || {
  log "⚠️ Realm cleanup failed, but we'll continue"
}

# Wait a bit more for everything to be fully initialized
log "Giving services a moment to fully initialize..."
sleep 10

# Step 1: Create fresh realm and client
log "Step 1: Creating fresh realm and client..."
/scripts/create-fresh-realm.sh || {
  log "❌ Failed to create fresh realm and client"
  exit 1
}
log "✅ Fresh realm and client created successfully"

# Step 2: Set up Vault integration
log "Step 2: Setting up Vault integration..."
/scripts/setup-vault-integration-fresh.sh || {
  log "❌ Failed to set up Vault integration"
  exit 1
}
log "✅ Vault integration set up successfully"

# Step 3: Perform initial client secret rotation
log "Step 3: Performing initial client secret rotation..."
/scripts/rotate-client-secret.sh || {
  log "❌ Failed to rotate client secret"
  exit 1
}
log "✅ Initial client secret rotation completed successfully"

# Step 4: Setup cron job for periodic rotation
log "Step 4: Setting up cron job for periodic rotation..."
mkdir -p /etc/cron.d
mkdir -p /var/log

# Create a cron script that will be run by cron
cat > /scripts/cron-rotate-client-secret.sh << 'EOF'
#!/bin/bash
echo "Running scheduled client secret rotation at $(date)"
/scripts/rotate-client-secret.sh
EOF

chmod +x /scripts/cron-rotate-client-secret.sh

# Add the cron job
echo "0 2 * * * /scripts/cron-rotate-client-secret.sh >> /var/log/cron.log 2>&1" > /etc/cron.d/client-secret-rotation
chmod 0644 /etc/cron.d/client-secret-rotation

# Load the crontab
if command -v crond &> /dev/null; then
  # Install crontab
  crontab /etc/cron.d/client-secret-rotation
  log "✅ Cron job installed successfully"
else
  log "⚠️ WARNING: cron daemon not available, scheduled rotation will not work"
fi

log "🎉 Auto-initialization completed successfully!"
log "The environment is now ready for use."
log "Client secrets will be rotated daily at 2 AM."

# Check if crond is available and start it if in daemon mode
if [ "$1" = "daemon" ]; then
  log "Starting daemon mode..."
  if command -v crond &> /dev/null; then
    log "Starting cron daemon..."
    crond -f
  else
    log "No cron daemon available, using sleep loop..."
    log "⚠️ WARNING: Cron not available, client secrets will not be automatically rotated"
    while true; do
      sleep 3600
    done
  fi
fi 