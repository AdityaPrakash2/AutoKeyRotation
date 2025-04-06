#!/bin/bash
echo "Running scheduled client secret rotation at $(date)"
/scripts/rotate-client-secret.sh
