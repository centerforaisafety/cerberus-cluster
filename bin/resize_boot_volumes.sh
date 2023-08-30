#!/bin/bash

# New size for boot volumes
echo "Setting New Size"
NEW_SIZE_IN_GB="100"

# Compartment Id
COMPARTMENT_ID=""

# Availability Domain
AVAILABILITY_DOMAIN=""

# Instance Pool Id
INSTANCE_POOL_ID=""

# Commands to run inside the instance for filesystem expansion
FS_EXPAND_CMDS="
sudo dd iflag=direct if=/dev/oracleoci/oraclevda of=/dev/null count=1;
echo '1' | sudo tee /sys/class/block/\$(readlink /dev/oracleoci/oraclevda | cut -d'/' -f 2)/device/rescan;
yes | sudo /usr/libexec/oci-growfs;
"

# Get instance ids
INSTANCE_IDS_JSON=$(oci compute-management instance-pool list-instances --compartment-id "$COMPARTMENT_ID" --instance-pool-id "$INSTANCE_POOL_ID" --query 'data[*].id')

# Remove square brackets and commas
CLEANED_INPUT="${INSTANCE_IDS_JSON//[\[\],\"]}"
CLEANED_INPUT="${CLEANED_INPUT// /}"

# Remove leading and trailing whitespace
CLEANED_INPUT=$(while IFS= read -r line; do
    echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[[:space:]]\+/ /g'
done <<< "$CLEANED_INPUT")

# Remove leading newline
CLEANED_INPUT=$(echo "$CLEANED_INPUT" | sed '/./,$!d')

# Get details for each instance in the list
while IFS= read -r INSTANCE_ID; do
    # Get name of instance
    echo 'Get name of instance'
    INSTANCE_DETAILS=$(oci compute instance get --instance-id "$INSTANCE_ID" --query 'data.{InstanceName:"display-name"}' --output json)
    INSTANCE_NAME=$(echo "$INSTANCE_DETAILS" | jq -r '.InstanceName')
    echo "$INSTANCE_NAME"

    # Get boot volume id of instance
    echo 'Get boot volume id of instance'
    BOOT_VOLUME_ATTACHMENT_DETAILS=$(oci compute boot-volume-attachment list --availability-domain "$AVAILABILITY_DOMAIN" --compartment-id "$COMPARTMENT_ID" --instance-id "$INSTANCE_ID" --query 'data[0].{BootVolumeId:"boot-volume-id"}' --output json)
    BOOT_VOLUME_ID=$(echo "$BOOT_VOLUME_ATTACHMENT_DETAILS" | jq -r '.BootVolumeId')
    echo "$BOOT_VOLUME_ID"

    # Create a backup for the boot volume
    echo "Creating backup for boot volume: $BOOT_VOLUME_ID"
    oci bv boot-volume-backup create --boot-volume-id "$BOOT_VOLUME_ID" --wait-for-state "AVAILABLE"

    # Resize the boot volume
    echo "Resizing boot volume: $BOOT_VOLUME_ID to $NEW_SIZE_IN_GB GB"
    oci bv boot-volume update --boot-volume-id "$BOOT_VOLUME_ID" --size-in-gbs "$NEW_SIZE_IN_GB" --wait-for-state "AVAILABLE"
done <<< "$CLEANED_INPUT"

# Soft reset the instance
echo "Restarting all instances"
oci compute-management instance-pool reset --instance-pool-id "$INSTANCE_POOL_ID" --max-wait-seconds 3000 --wait-for-state "RUNNING"

# SSH into each instance and perform filesystem expansions
while IFS= read -r INSTANCE_ID; do
    
    # Get name of instance
    echo 'Get name of instance'
    INSTANCE_DETAILS=$(oci compute instance get --instance-id "$INSTANCE_ID" --query 'data.{InstanceName:"display-name"}' --output json)
    INSTANCE_NAME=$(echo "$INSTANCE_DETAILS" | jq -r '.InstanceName')
    echo "$INSTANCE_NAME"

    # Get private ip of instance
    echo 'Get private ip of instance'
    VNIC_ATTACHMENT_DETAILS=$(oci compute vnic-attachment list --compartment-id "$COMPARTMENT_ID" --instance-id "$INSTANCE_ID" --query 'data[0].{VnicId:"vnic-id"}' --output json)
    VNIC_ID=$(echo "$VNIC_ATTACHMENT_DETAILS" | jq -r '.VnicId')
    VNIC_DETAILS=$(oci network vnic get --vnic-id "$VNIC_ID" --query 'data.{PrivateIp:"private-ip"}' --output json)
    PRIVATE_IP=$(echo "$VNIC_DETAILS" | jq -r '.PrivateIp')
    echo "$PRIVATE_IP"

    # SSH into the instance and perform filesystem expansion
    echo "Expanding filesystem on: $INSTANCE_NAME"
    ssh -n -o "StrictHostKeyChecking no" opc@$PRIVATE_IP "$FS_EXPAND_CMDS"

    echo "Instance $INSTANCE_NAME processed!"
done <<< "$CLEANED_INPUT"