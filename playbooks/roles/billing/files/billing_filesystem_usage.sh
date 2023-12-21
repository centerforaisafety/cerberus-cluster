#!/bin/bash

# Description:
#   This script automates the process of collecting weka filesystem usage data for specific paid users from the Weka filesystem. 
#   After extracting the relevant usage data, the script aggregates this information and inserts it into a MySQL database. 

# Features:
#   - Efficient Data Collection: Gathers filesystem usage data from the Weka filesystem for a predefined set of paid users.
#   - Data Filtering: Isolates the usage data of interest by filtering out non-paid users.
#   - Database Integration: Inserts the processed data into a MySQL database using a single, efficient batch INSERT query.
#   - Customizable User List: Currently uses a static list of paid users, but can be modified to dynamically fetch this list from an external source.

# Usage:
#   - Configure the script with appropriate MySQL database credentials and Weka filesystem access.
#   - Schedule the script to run on a fixed interval with a cronjob.
#   - Ensure the script has executable permissions (use 'chmod +x script_name.sh' if necessary).

# Requirements:
#   - Bash shell environment.
#   - Access to the Weka filesystem with the necessary permissions to execute the 'weka fs quota list' command.
#   - MySQL client installed and network access to the MySQL database server.
#   - Necessary permissions to execute and schedule the script in the operating environment.

# Security Note:
#   - The script currently contains a placeholder for database credentials, which should be handled securely. 

# Global Variables
TABLE='usage_records'
START_TIME=$(date -d "-1 hour" +"%Y-%m-%d %H:00:00")
END_TIME=$(date -d "-1 hour" +"%Y-%m-%d %H:59:59")
MYSQL_HOST_IP=''
PASSWORD=''  # TODO: Refactor to use a secure location for the db credientials.
DB_NAME='billing'
declare -A TOTAL_FILESYSTEM_USAGE_PER_USER

# Associative array of paid users
# TODO: Refactor this to be dynamic
declare -A PAID_USERS
PAID_USERS['florian_tramer']=10096

# Function to get weka filesystem usage per user
get_filesystem_usage_per_user() {
    local usage_per_user=$(weka fs quota list --all --output path,used | sed 's/default:\///')
    while read -r line; do
        local USER_NAME GIGABYTES
        read -r USER_NAME GIGABYTES <<< $(awk '{print $1, $2}' <<< "$line")
        
        # Filter for paid users only
        if [[ ${PAID_USERS[$USER_NAME]+_} ]]; then
            USER_ID=${PAID_USERS[$USER_NAME]}
            TOTAL_FILESYSTEM_USAGE_PER_USER[$USER_ID]=$GIGABYTES
        fi
    done <<< "$usage_per_user"
}

# Function to insert filesystem usage data into the database with a single INSERT query
insert_filesystem_usage_into_db() {
    local sql_values=()
    for user_id in "${!TOTAL_FILESYSTEM_USAGE_PER_USER[@]}"; do
        local gigabytes=${TOTAL_FILESYSTEM_USAGE_PER_USER[$user_id]}
        sql_values+=("($user_id, 3, '$START_TIME', '$END_TIME', $gigabytes)")
    done

    if [ ${#sql_values[@]} -eq 0 ]; then
        # No data to insert
        return
    fi

    local sql="INSERT INTO $TABLE (user_id, resource_spec_id, usage_start_time, usage_end_time, usage_amount) VALUES "
    sql+=$(IFS=','; echo "${sql_values[*]}")
    sql+=";"

    mysql -h $MYSQL_HOST_IP -u root -p$PASSWORD $DB_NAME -e "$sql"
}

# Main script logic
get_filesystem_usage_per_user
insert_filesystem_usage_into_db

