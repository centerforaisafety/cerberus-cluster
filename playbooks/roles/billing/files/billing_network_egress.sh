#!/bin/bash

# Description:
#   This script is designed to monitor and record network egress traffic usage by users across multiple hosts.
#   It gathers network usage data from each host, aggregates the data by user, and then stores this
#   information in a database for billing and tracking purposes. The script is tailored for an environment
#   with Slurm Workload Manager, iptables, SSH, and MySQL.

# Features:
#   - Gathers network usage data from hosts listed by Slurm Workload Manager.
#   - Processes and aggregates network usage data by user ID.

# Usage:
#   1. Update the PARTITION variable to match the name of the partition that contains paid users.
#      - Example: PARTITION='paid'
#      - If this is not done, the script will not be able to retrieve usage data.
#   2. This script should be scheduled to run hourly with a cron job.
#      - Example cron job: 0 * * * * /opt/oci-hpc/billing/billing_network_egress.sh

# Requirements:
#   - Slurm Workload Manager: for fetching the list of hosts.
#   - iptables: for gathering network usage statistics.
#   - SSH: for remote execution of commands on listed hosts.
#   - MySQL: for storing the aggregated network usage data.
#

# Gather list of hosts from Slurm
PARTITION='grayswan' # Add paid partition
HOSTS=$(sudo sinfo -p $PARTITION -S "%n" -o "%n" | tail -n +2)

# Global Variables
TABLE='usage_records'
START_TIME=$(date -d "-1 hour" +"%Y-%m-%d %H:00:00")
END_TIME=$(date -d "-1 hour" +"%Y-%m-%d %H:59:59")
MYSQL_HOST_IP=$(grep 'billing_mysql_ip' /etc/ansible/hosts | cut -d '=' -f2)
MYSQL_USERNAME=$(grep 'billing_mysql_db_admin_username' /etc/ansible/hosts | cut -d '=' -f2)
MYSQL_PASSWORD=$(grep 'billing_mysql_db_admin_password' /etc/ansible/hosts | cut -d '=' -f2)
DB_NAME='billing'
declare -A TOTAL_NETWORK_USAGE_PER_USER

# Function to get network usage per user from a host
# Arguments:
#   $1 - Hostname
get_network_usage_per_user() {
    local host=$1
    local IPTABLE_CMD='sudo iptables -L USER_TRAFFIC -v -x -n | awk '\''NR>3 {print $2, $13}'\'' && sudo iptables -Z USER_TRAFFIC'
    RESULT=$(ssh "$host" "$IPTABLE_CMD")
    echo "$RESULT"
}

# Function to process and accumulate network usage
# Arguments:
#   $1 - Network usage data for a specific host
process_network_usage() {
    local usage_per_user=$1
    while read -r line; do
        local bytes user_id
        read -r bytes user_id <<< $(awk '{print $1, $2}' <<< "$line")
        TOTAL_NETWORK_USAGE_PER_USER[$user_id]=$((TOTAL_NETWORK_USAGE_PER_USER[$user_id] + bytes))
    done <<< "$usage_per_user"
}

# Function to insert network usage data into the database with a single INSERT query
insert_network_usage_into_db() {
    local sql_values=()
    for user_id in "${!TOTAL_NETWORK_USAGE_PER_USER[@]}"; do
        local bytes=${TOTAL_NETWORK_USAGE_PER_USER[$user_id]}
        sql_values+=("($user_id, 2, '$START_TIME', '$END_TIME', $bytes)")
    done

    if [ ${#sql_values[@]} -eq 0 ]; then
        # No data to insert
        return
    fi

    local sql="INSERT INTO $TABLE (user_id, resource_spec_id, usage_start_time, usage_end_time, usage_amount) VALUES "
    sql+=$(IFS=','; echo "${sql_values[*]}")
    sql+=";"

    mysql -h $MYSQL_HOST_IP -u $MYSQL_USERNAME -p$MYSQL_PASSWORD $DB_NAME -e "$sql" 2>&1 | grep -v "mysql"
}

# Main script logic
# Iterate over each host to gather network usage data. If we have data then process it. 
for host in $HOSTS; do
    usage_per_user=$(get_network_usage_per_user "$host")
    
    # Check if the result is empty
    if [ -z "$usage_per_user" ]; then
        echo 'empty'
        continue
    fi

    process_network_usage "$usage_per_user"
done

# Insert the accumulated network usage data into the database
insert_network_usage_into_db