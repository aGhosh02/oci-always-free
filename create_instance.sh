#!/bin/bash

# Add timestamp to logs
echo "-------------------------------------------"
echo "Starting instance creation attempt at $(date)"

# Create a lock file to prevent overlapping runs
LOCK_FILE="/tmp/instance_creation.lock"

if [ -e "$LOCK_FILE" ]; then
  # Check if process is still running
  PID=$(cat "$LOCK_FILE")
  if ps -p "$PID" > /dev/null; then
    echo "Previous instance creation process (PID: $PID) is still running. Exiting."
    exit 0
  else
    echo "Found stale lock file. Previous process must have crashed. Removing lock."
    rm -f "$LOCK_FILE"
  fi
fi

# Create new lock file
echo $$ > "$LOCK_FILE"

# Clean up lock file when script exits
trap 'rm -f "$LOCK_FILE"' EXIT


export C=ocid1.tenancy.oc1..aaaaaaaalj3wkj4jzguk5drokrxx2yr5zppmokn7nni6o3ldiwlcbz64kqkq
export S=ocid1.subnet.oc1.iad.aaaaaaaalbpl6vaph2ypbmqfmjhotjtwx3gevx62xp2vwjilhvrzpzumavea
export I=ocid1.image.oc1.iad.aaaaaaaa5rxxb24tifnuklbdr3uqe3jnoeojal5evtkwysu37m6sxnod2rqa

# Function to send notification to ntfy.sh
send_notification() {
    local title="$1"
    local message="$2"
    local priority="${3:-default}"
    
    curl -H "Title: $title" \
         -H "Priority: $priority" \
         -H "Tags: computer,white_check_mark" \
         -d "$message" \
         https://ntfy.arghyaghosh.cloud/oci
}

# Function to attempt instance launch
launch_instance() {
    local ad=$1
    echo "Attempting to launch instance in Availability Domain: $ad"
    
    # Store the output of the command for later use
    local output=$(oci compute instance launch \
     --availability-domain "$ad" \
     --compartment-id $C \
     --shape VM.Standard.A1.Flex \
     --subnet-id $S \
     --assign-private-dns-record true \
     --assign-public-ip false \
     --availability-config file:///oracle/config/availabilityConfig.json \
     --display-name "arghya-vm-${ad##*-}" \
     --image-id $I \
     --instance-options file:///oracle/config/instanceOptions.json \
     --shape-config file:///oracle/config/shapeConfig.json \
     --ssh-authorized-keys-file /oracle/config/ssh-key-2025-03-23.key.pub 2>&1)

    # Check the output content rather than relying on the status code
    if echo "$output" | grep -q "ServiceError"; then
        # Check if the error is due to capacity issues
        if echo "$output" | grep -q "Out of host capacity"; then
            echo "ERROR: No capacity available in $ad"
            echo "$output"
            # Return a specific code for capacity issues
            return 2
        else
            echo "ERROR: Failed to launch instance in $ad"
            echo "$output"
            return 1
        fi
    else
        echo "SUCCESS: Instance created in $ad"
        # Extract instance ID from the output
        local instance_id=$(echo "$output" | grep -o '"id": "[^"]*' | cut -d'"' -f4)
        echo "Instance ID: $instance_id"
        return 0
    fi
}

# Try each availability domain
for ad_number in 1 2 3; do
    AD="REED:US-ASHBURN-AD-${ad_number}"
    
    if launch_instance "$AD"; then
        success_message="Successfully launched instance in $AD"
        echo "$success_message"
        
        # Send success notification
        # hostname=$(hostname)
        send_notification "OCI Instance Launch Successful" "Instance launched in $AD" "high"
        
        exit 0
    else
        status=$?
        if [ $status -eq 2 ]; then
            echo "No capacity in $AD. Trying next availability domain..."
            # send_notification "OCI Instance Capacity Issue" "No capacity available in $AD. Trying next availability domain." "low"
        else
            echo "Failed to launch instance in $AD. Trying next availability domain..."
        fi
    fi
done

# Clean up lock file before exit
rm -f "$LOCK_FILE"

# Send failure notification
# send_notification "OCI Instance Launch Failed" "Failed to launch instance in any availability domain due to capacity issues or other errors." "high"

echo "Failed to launch instance in any availability domain at $(date)"
exit 1