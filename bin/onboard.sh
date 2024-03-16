#!/bin/bash

# Variables (Replace these with actual values or pass them as arguments)
lab_name='' # john_smith_lab
researcher_name='' # john_smith
full_name='' # John Smith
user_password=''
parent_account='' 
ssh_key=''

# Check if lab exists on the cluster
if cluster group list | grep -w "$lab_name"; then
    echo "Lab already exists. Moving on to researcher onboarding."
else
    # Lab Onboarding
    echo "Onboarding new lab: $lab_name"
    # Add the lab group
    cluster group create "$lab_name"
    # Add slurm lab account
    sudo sacctmgr add account --immediate "$lab_name" Parent="$parent_account" Description="Professor $lab_name Lab" Organization=Prof_"$lab_name"
fi

# Researcher Onboarding
echo "Onboarding new researcher: $researcher_name"
# Retrieve the lab group id
group_id=$(cluster group list | grep -wA1 "$lab_name" | grep gidNumber | awk '{print $2}')
# Create cluster user
cluster user add "$researcher_name" --gid "$group_id" --password "$user_password" --name "$full_name"
# Create Slurm user
sudo sacctmgr create user --immediate "$researcher_name" DefaultAccount="$lab_name"
# Add SSH key 
echo "$ssh_key" | sudo tee -a /data/$researcher_name/.ssh/authorized_keys
# Set Filesystem Quotas
sudo weka fs quota set "/data/$researcher_name" --hard 1TB --grace 1d
echo "Onboarding process completed for $researcher_name."