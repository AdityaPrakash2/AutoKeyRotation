#!/bin/bash
set -e

echo "=== Starting Keycloak Client Secret Rotation System ==="
echo "This script will start all services and automatically initialize the environment."

# Check if docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed or not in PATH. Please install Docker first."
    exit 1
fi

# Check if docker-compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is not installed or not in PATH. Please install Docker Compose first."
    exit 1
fi

# Check if containers are already running
running_containers=$(docker ps --format '{{.Names}}' | grep -E 'keycloak|vault|postgres|client-secret-rotation' | wc -l)
if [ "$running_containers" -gt 0 ]; then
    echo "⚠️  Some containers are already running. Would you like to stop them first? (y/n)"
    read -r stop_containers
    if [[ "$stop_containers" =~ ^[Yy]$ ]]; then
        echo "Stopping running containers..."
        docker-compose down
    fi
fi

# Start the containers
echo "Starting all services with Docker Compose..."
docker-compose up -d

echo "Services are starting up!"
echo "The auto-initialization script will now run in the background."

# Show log for the client-secret-rotation container
echo ""
echo "Showing logs from the client-secret-rotation container..."
echo "Press Ctrl+C to stop viewing logs (services will continue running)"
echo ""
docker logs -f client-secret-rotation 