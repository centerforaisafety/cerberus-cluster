#!/bin/bash

# Script Name: Configure For Weka
# Description:
#   This script is designed to configure remote hosts to support the Weka filesystem on a cluster. 
#   Given a list of remote host names (provided in a specified file), it performs the following operations on each host:
#   - Creates necessary directories on shared filesystems and sets their permissions.
#   - Binds the host-specific directory to `/mnt/localdisk` as a replacement for on node storage.
#   - Creates several subdirectories under `/mnt/localdisk` for enroot and slurm usage.
#   - Sets appropriate permissions and ownership for these directories.
#
# Host File Format:
#   The host file should contain a list of remote host names. Each name can be an IP address or in the format 'compute-permanent-node-#'. 
#   Host names should be separated by new lines.
#
#   Example:
#      compute-permanent-node-35
#      compute-permanent-node-84
#      ...
#      compute-permanent-node-990
#
# Prerequisites:
#   - SSH access to each of the remote hosts listed in the provided file.
#   - Proper sudo privileges on the local and remote machines.
#   - The script should be executed on a node that intends to be part of the Weka cluster.
#
# Usage:
#   ./script_name.sh [path_to_hosts_file]

function usage() {
    echo "Usage: $0 [path_to_hosts_file]"
    exit 1
}

# Check for command line arguments for hosts file
if [ "$#" -eq 1 ]; then
    HOSTS_FILE="$1"
else
    usage
fi

# Ensure the hosts file exists
if [ ! -f "$HOSTS_FILE" ]; then
    echo "Error: File '$HOSTS_FILE' not found!"
    exit 1
fi

# Create directory on shared filesystem
echo "Creating directory on shared filesystem..."
sudo mkdir -p /data/nodes_local
sudo chmod 700 /data/nodes_local

# Process each remote host
while IFS= read -r remote_host; do
    echo "--------------------------"
    echo "Processing $remote_host"
    echo "--------------------------"

    # Use a single SSH session to execute the commands
    ssh -t "$remote_host" << EOF || echo "Error processing $remote_host"
sudo mkdir -p /data/nodes_local/$remote_host
sudo chmod 700 /data/nodes_local/$remote_host
sudo mkdir -p /mnt/localdisk
sudo mount --bind /data/nodes_local/$remote_host /mnt/localdisk
sudo mkdir -p /mnt/localdisk/enroot
sudo mkdir -p /mnt/localdisk/enroot/enroot_tmp
sudo mkdir -p /mnt/localdisk/enroot/enroot_cache
sudo mkdir -p /mnt/localdisk/enroot/enroot_runtime
sudo mkdir -p /mnt/localdisk/enroot/enroot_data
sudo mkdir -p /mnt/localdisk/slurm_tmp
sudo chown -R opc:privilege /mnt/localdisk/enroot
sudo chown -R root:slurm /mnt/localdisk/slurm_tmp
sudo chmod 777 /mnt/localdisk
sudo chmod -R 770 /mnt/localdisk/slurm_tmp
sudo chmod -R 777 /mnt/localdisk/enroot
EOF

    echo "$remote_host completed."
done < "$HOSTS_FILE"

