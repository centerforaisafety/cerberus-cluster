#!/bin/bash

# Variables (Replace these with actual values or pass them as arguments)
lab_name='' # john_smith
cluster_username='' # john_smith
full_name='' # John Smith
user_password=''
parent_account=''
ssh_key=''

# Billing variables
add_billing=false
billing_address=''
billing_email=''
a100_price=''
network_egress_price=''
filesystem_price=''

# Function to exit script upon error
function error_exit {
    echo "$1" 1>&2
    exit 1
}

# Check if cluster command is available
cluster || error_exit "Cluster command is not available."

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

    if [ "$add_billing" = true ]; then
        group_id=$(cluster group list | grep -wA1 "$lab_name" | grep gidNumber | awk '{print $2}')
        mysql --defaults-extra-file=/home/ubuntu/.billing.cnf -e "INSERT INTO billing.accounts (account_id, account_name, email, billing_address) VALUES ($group_id, '$lab_name', '$billing_email', '$billing_address');"
        mysql --defaults-extra-file=/home/ubuntu/.billing.cnf -e "INSERT INTO billing.pricing (account_id, resource_spec_id, price_per_unit, price_effective_date) VALUES ($group_id, 1, $a100_price, CURRENT_DATE);"
        mysql --defaults-extra-file=/home/ubuntu/.billing.cnf -e "INSERT INTO billing.pricing (account_id, resource_spec_id, price_per_unit, price_effective_date) VALUES ($group_id, 2, $network_egress_price, CURRENT_DATE);"
        mysql --defaults-extra-file=/home/ubuntu/.billing.cnf -e "INSERT INTO billing.pricing (account_id, resource_spec_id, price_per_unit, price_effective_date) VALUES ($group_id, 3, $filesystem_price, CURRENT_DATE);"
    fi
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
sudo weka fs quota set "/data/$cluster_username" --hard 500GB --grace 1d || error_exit "Failed to set filesystem quotas for: $cluster_username"

if [ "$add_billing" = true ]; then
    user_id=$(cluster user list | grep -wA1 "$cluster_username" | grep uidNumber | awk '{print $2}')
    mysql --defaults-extra-file=/home/ubuntu/.billing.cnf -e "INSERT INTO billing.users (user_id, account_id, user_name) VALUES ($user_id, $group_id, '$cluster_username');" 
fi

# Update iptables rules for egress tracking
ansible-playbook /opt/oci-hpc/playbooks/sync_iptables_for_usage_tracking.yml

echo "Onboarding process completed for $cluster_username."
