#!/bin/bash

# Set proper permissions for the oracle user
chown -R oracle:oracle /oracle

# Start cron service in background
echo "Starting cron service..."
crond

if [ "$1" = "run" ]; then
    echo "Container started. Cron job will execute create_instance.sh every 5 minutes."
    echo "Check logs at /oracle/logs/instance_creation.log"
    
    # Run script once immediately
    su - oracle -c "/oracle/create_instance.sh >> /oracle/logs/instance_creation.log 2>&1"
    
    # Keep container running
    tail -f /dev/null
elif [ "$1" = "run-once" ]; then
    echo "Running create_instance.sh once..."
    su - oracle -c "/oracle/create_instance.sh"
else
    # Execute OCI command
    su - oracle -c "oci $*"
fi
