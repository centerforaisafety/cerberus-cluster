#!/bin/bash

# Description:
#   This script is designed to monitor and record network egress traffic usage by users across multiple hosts.
#   It gathers network usage data from each host, aggregates the data by user, and then stores this
#   information in a database for billing or tracking purposes. The script is tailored for an environment
#   with Slurm Workload Manager, iptables, SSH, and MySQL.
#
# Features:
#   - Gathers network usage data from hosts listed by Slurm Workload Manager.
#   - Processes and aggregates network usage data by user ID.
#
# Usage:
#   The script is to be scheduled to run on fixed intervals using a cron job.
#
# Requirements:
#   - Slurm Workload Manager: for fetching the list of hosts.
#   - iptables: for gathering network usage statistics.
#   - SSH: for remote execution of commands on listed hosts.
#   - MySQL: for storing the aggregated network usage data.
#
# Security Note:
#   TODO: The script contains hardcoded database credentials. Move the credentials to a secure location. 

# Gather list of hosts from Slurm
PARTITION=''
HOSTS=$(sudo sinfo -p $PARTITION -S "%n" -o "%n" | tail -n +2)

# Global Variables
TABLE='usage_records'
START_TIME=$(date -d "-1 hour" +"%Y-%m-%d %H:00:00")
END_TIME=$(date -d "-1 hour" +"%Y-%m-%d %H:59:59")
HOST=''
PASSWORD=''  # Consider moving to a more secure method
DB_NAME='billing'
declare -A TOTAL_NETWORK_USAGE_PER_USER

# Function to get network usage per user from a host
# Arguments:
#   $1 - Hostname
get_network_usage_per_user() {
    local host=$1
    local IPTABLE_CMD='sudo iptables -L USER_TRAFFIC -v -n | awk '\''NR>3 {print $2, $13}'\'' && sudo iptables -Z USER_TRAFFIC'
    ssh "$host" "$IPTABLE_CMD"
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

    mysql -h $HOST -u root -p$PASSWORD $DB_NAME -e "$sql"
}

# Main script logic
# Iterate over each host to gather and process network usage data
for host in $HOSTS; do
    usage_per_user=$(get_network_usage_per_user "$host")
    process_network_usage "$usage_per_user"
done

# Insert the accumulated network usage data into the database
insert_network_usage_into_db

