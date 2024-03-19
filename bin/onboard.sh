#!/bin/bash

# Variables (Replace these with actual values or pass them as arguments)
lab_name='' # john_smith
cluster_username='' # john_smith
full_name='Steven Basart 3' # John Smith
user_password='password'
parent_account='root'
ssh_key='ssh-key'

# Function to exit script upon error
function error_exit {
    echo "$1" 1>&2
    exit 1
}

# Check if lab exists on the cluster
if cluster group list | grep -w "$lab_name"; then
    echo "Lab already exists. Moving on to researcher onboarding."
else
    # Lab Onboarding
    echo "Onboarding new lab: $lab_name"
    # Add the lab group
    cluster group create "$lab_name" || error_exit "Failed to create lab group: $lab_name"
    # Add slurm lab account
    sudo sacctmgr add account --immediate "$lab_name" Parent="$parent_account" Description="$lab_name Lab" Organization=Prof_"$lab_name" || error_exit "Failed to add Slurm lab account for: $lab_name"
fi

# Researcher Onboarding
echo "Onboarding new researcher: $cluster_username"
# Retrieve the lab group id
group_id=$(cluster group list | grep -wA1 "$lab_name" | grep gidNumber | awk '{print $2}')
# Create cluster user
cluster user add "$cluster_username" --gid "$group_id" --password "$user_password" --name "$full_name" || error_exit "Failed to add cluster user: $cluster_username"
# Create Slurm user
sudo sacctmgr create user --immediate "$cluster_username" DefaultAccount="$lab_name" || error_exit "Failed to create Slurm user for: $cluster_username"
# Add SSH key 
echo "$ssh_key" | sudo tee -a /data/$cluster_username/.ssh/authorized_keys
# Set Filesystem Quotas
sudo weka fs quota set "/data/$cluster_username" --hard 1TB --grace 1d || error_exit "Failed to set filesystem quotas for: $cluster_username"
echo "Onboarding process completed for $cluster_username."
