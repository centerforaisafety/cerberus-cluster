#!/bin/bash

NEW_SIZE_IN_GB="100"
COMPARTMENT_ID=""
AVAILABILITY_DOMAIN=""
INSTANCE_POOL_ID=""

# Commands to run inside the instance for filesystem expansion
FS_EXPAND_CMDS="
sudo dd iflag=direct if=/dev/oracleoci/oraclevda of=/dev/null count=1;
echo '1' | sudo tee /sys/class/block/\$(readlink /dev/oracleoci/oraclevda | cut -d'/' -f 2)/device/rescan;
yes | sudo /usr/libexec/oci-growfs;
"

INSTANCE_IDS=$(oci compute-management instance-pool list-instances --compartment-id "$COMPARTMENT_ID" --instance-pool-id "$INSTANCE_POOL_ID" --query 'data[*].id')

# Remove square brackets and commas
INSTANCE_IDS="${INSTANCE_IDS//[\[\],\"]}"
INSTANCE_IDS="${INSTANCE_IDS// /}"

# Remove leading and trailing whitespace
INSTANCE_IDS=$(while IFS= read -r line; do
    echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]\+/ /g'
done <<< "$INSTANCE_IDS")

# Remove leading newline
INSTANCE_IDS=$(echo "$INSTANCE_IDS" | sed '/./,$!d')

echo "Resize Boot Volume to $NEW_SIZE_IN_GB GB on all compute nodes."
while IFS= read -r INSTANCE_ID; do
    # Get name of instance
    INSTANCE_DETAILS=$(oci compute instance get --instance-id "$INSTANCE_ID" --query 'data.{InstanceName:"display-name"}' --output json)
    INSTANCE_NAME=$(echo "$INSTANCE_DETAILS" | jq -r '.InstanceName')
    echo "Processing: $INSTANCE_NAME"
    # Get boot volume id of instance
    BOOT_VOLUME_ATTACHMENT_DETAILS=$(oci compute boot-volume-attachment list --availability-domain "$AVAILABILITY_DOMAIN" --compartment-id "$COMPARTMENT_ID" --instance-id "$INSTANCE_ID" --query 'data[0].{BootVolumeId:"boot-volume-id"}' --output json)
    BOOT_VOLUME_ID=$(echo "$BOOT_VOLUME_ATTACHMENT_DETAILS" | jq -r '.BootVolumeId')

    # Create a backup for the boot volume
    echo -n '--> Creating backup...'
    oci bv boot-volume-backup create --boot-volume-id "$BOOT_VOLUME_ID" --wait-for-state "AVAILABLE" &> /dev/null
    echo '✅'

    # Resize the boot volume
    echo -n '--> Resizing boot volume...'
    oci bv boot-volume update --boot-volume-id "$BOOT_VOLUME_ID" --size-in-gbs "$NEW_SIZE_IN_GB" --wait-for-state "AVAILABLE" &> /dev/null
    echo '✅' 
done <<< "$INSTANCE_IDS"

# Soft reset the instance
echo "Restarting all instances."
oci compute-management instance-pool reset --instance-pool-id "$INSTANCE_POOL_ID" --max-wait-seconds 3000 --wait-for-state "RUNNING" &> /dev/null

let SLEEP_TIME_IN_MINUTES=20
echo "Entering sleep for $SLEEP_TIME_IN_MINUTES to give compute nodes more time to restart."
let "SLEEP_TIME_IN_SECONDS=$SLEEP_TIME_IN_MINUTES * 60"
sleep $SLEEP_TIME_IN_SECONDS

# SSH into each instance and perform filesystem expansions
while IFS= read -r INSTANCE_ID; do
    # Get name of instance
    INSTANCE_DETAILS=$(oci compute instance get --instance-id "$INSTANCE_ID" --query 'data.{InstanceName:"display-name"}' --output json)
    INSTANCE_NAME=$(echo "$INSTANCE_DETAILS" | jq -r '.InstanceName')

    # SSH into the instance and perform filesystem expansion
    echo -n "Expanding filesystem on: $INSTANCE_NAME..."
    ssh -n -o "StrictHostKeyChecking no" opc@$INSTANCE_NAME "$FS_EXPAND_CMDS" &> /dev/null
    echo '✅'
done <<< "$INSTANCE_IDS"