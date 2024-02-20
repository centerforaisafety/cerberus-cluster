#!/bin/bash

# Description:
#   This script check and records the existence of any paid partitions. 
#   It retrieves usage data, distinguishes between different GPU types (A100 and H100), 
#   and inserts summarized data into a database for billing purposes.
#
# Usage:
#    1. Update the PARTITION variable to match the name of the partition that is used by paid users.
#      - Example: PARTITION='paid'
#      - If this is not done, the script will not be able to retrieve usage data.
#    2. This script should be scheduled to run daily at 00:00:00 with a cron job.
#      - Example cron job: 0 0 * * * /opt/oci-hpc/billing/billing_gpu_usage.sh
#

# Global Variables
PARTITION='' # Add paid partition

TABLE='usage_records'
DATE=$(date -d "-1 day" +"%Y-%m-%d")
MYSQL_HOST_IP=$(grep 'billing_mysql_ip' /etc/ansible/hosts | cut -d '=' -f2)
MYSQL_USERNAME=$(grep 'billing_mysql_db_admin_username' /etc/ansible/hosts | cut -d '=' -f2)
MYSQL_PASSWORD=$(grep 'billing_mysql_db_admin_password' /etc/ansible/hosts | cut -d '=' -f2)
DB_NAME='billing'

# Associative arrays for each gpu type
declare -A TOTAL_A100_USAGE_PER_USER
declare -A TOTAL_H100_USAGE_PER_USER

# Associative array of paid users
declare -A PAID_USERS

# Function to get a list of paid users from the database
get_paid_users_from_db() {
    local sql="SELECT user_name, user_id FROM users"
    local result=$(mysql -h $MYSQL_HOST_IP -u $MYSQL_USERNAME -p$MYSQL_PASSWORD $DB_NAME -e "$sql" 2>&1 | grep -v "mysql")
    
    # Check if the result is empty
    if [ -z "$result" ]; then
        return 0
    fi

    while read -r line; do
        local USERNAME USER_ID
        read -r USERNAME USER_ID <<< $(awk '{print $1, $2}' <<< "$line")
        PAID_USERS[$USERNAME]=$USER_ID
    done <<< "$result"
}

# Function to convert elapsed time in [days-]hours:minutes:seconds format to seconds
# Usage: convert_to_seconds $ELAPSED_TIME
convert_to_seconds() {
    ELAPSED_TIME=$1
    DAYS=0
    HOURS=0
    MINUTES=0
    SEC=0

    # Check if days are present in the time format
    if [[ $ELAPSED_TIME == *-* ]]; then
        DAYS=${ELAPSED_TIME%%-*}
        ELAPSED_TIME=${ELAPSED_TIME#*-}
    fi

    # Split the time into hours, minutes, and seconds
    IFS=':' read -ra TIME_PARTS <<< "$ELAPSED_TIME"
    HOURS=$((10#${TIME_PARTS[0]}))
    MINUTES=$((10#${TIME_PARTS[1]}))
    SEC=$((10#${TIME_PARTS[2]}))

    # Calculate total seconds
    TOTAL_SECONDS=$((DAYS * 86400 + HOURS * 3600 + MINUTES * 60 + SEC))
    echo $TOTAL_SECONDS
}

# Function to parse AllocTRES to extract gpu type
# Usage: extract_gpu_type $ALLOC_TRES
extract_gpu_type() {
    gpu_type=$(echo "$1" | grep -o 'gres/gpu:[^,]*' | cut -d ':' -f2 | cut -d '=' -f1)
    echo "$gpu_type"
}

# Function to parse AllocTRES to extract gpu quantity
# Usage: extract_gpu_quantity
extract_gpu_quantity() {
    gpu_quantity=""

    # Extract the string that contains 'gres/gpu:'
    gpu_info=$(echo "$1" | grep -o 'gres/gpu:[^,]*')

    if [ -n "$gpu_info" ]; then
        # Extract the quantity
        gpu_quantity=$(echo "$gpu_info" | cut -d '=' -f2)
    fi

    echo "$gpu_quantity"
}

# Function to get gpu usage per user
get_gpu_usage_per_user() {
    local usage_per_user=$(sacct -a -X --partition $PARTITION --format=user,elapsed,AllocTRES --starttime ${DATE}T00:00:00 --endtime ${DATE}T23:59:59 --state=bf,ca,cd,dl,f,nf,oom,pr,to --parsable2)
    while read -r line; do
        local USER_NAME ELAPSED_TIME ALLOC_TRES
        read -r USER_NAME ELAPSED_TIME ALLOC_TRES <<< $(awk -F '|' '{print $1, $2, $3}' <<< "$line")

        # Filter for paid users only
        if [[ ${PAID_USERS[$USER_NAME]+_} ]]; then
            USER_ID=${PAID_USERS[$USER_NAME]}
            SECONDS=$(convert_to_seconds $ELAPSED_TIME)
            GPU_TYPE=$(extract_gpu_type $ALLOC_TRES)
            GPU_QUANTITY=$(extract_gpu_quantity $ALLOC_TRES)

            # Filter by gpu type
            if [[ "$GPU_TYPE" == "a100" ]]; then
                TOTAL_A100_USAGE_PER_USER[$USER_ID]=$((TOTAL_A100_USAGE_PER_USER[$USER_ID] + $(($SECONDS * $GPU_QUANTITY))))
            elif [[ "$GPU_TYPE" == "h100" ]]; then
                TOTAL_H100_USAGE_PER_USER[$USER_ID]=$((TOTAL_H100_USAGE_PER_USER[$USER_ID] + $(($SECONDS * $GPU_QUANTITY))))
            fi
        fi
    done <<< "$usage_per_user"
}

# Function to insert gpu usage data into the database with a single INSERT query
insert_gpu_usage_into_db() {
    local sql_values=()

    # Append INSERT statements for a100 usage records
    for user_id in "${!TOTAL_A100_USAGE_PER_USER[@]}"; do
        local TOTAL_SECONDS=${TOTAL_A100_USAGE_PER_USER[$user_id]}
        sql_values+=("($user_id, 1, '${DATE} 00:00:00', '${DATE} 23:59:59', $TOTAL_SECONDS)")
    done

    # Append INSER statements for h100 usage records
    for user_id in "${!TOTAL_H100_USAGE_PER_USER[@]}"; do
        local TOTAL_SECONDS=${TOTAL_H100_USAGE_PER_USER[$user_id]}
        sql_values+=("($user_id, 4, '${DATE} 00:00:00', '${DATE} 23:59:59', $TOTAL_SECONDS)")
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
get_paid_users_from_db
get_gpu_usage_per_user
insert_gpu_usage_into_db