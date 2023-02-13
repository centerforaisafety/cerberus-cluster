#!/bin/bash

###################################################
# Description:
#   This script collects weka filesystem usage for paid users from the Weka filesystem. 
#   After extracting the relevant usage data, the script aggregates this information and inserts it into a MySQL database. 
#
# Features:
#   - Efficient Data Collection: Gathers filesystem usage data from the Weka filesystem for paid users.
#   - Data Filtering: Isolates the usage data of interest by filtering out non-paid users.
#   - Database Integration: Inserts the processed data into a MySQL database using a single, efficient batch INSERT query.
#   - Dynamic User List: Dynamically fetchs this list from an external source.
#
# Usage:
#   1. This script should be scheduled to run hourly with a cron job.
#      - Example cron job: 0 * * * * /opt/oci-hpc/billing/filesystem.sh
#
# Requirements:
#   - Bash shell environment.
#   - Access to the Weka filesystem with the necessary permissions to execute the 'weka fs quota list' command.
#   - MySQL client installed and network access to the MySQL database server.
#   - Properly configured MySQL credentials using mysql_config_editor
#   - Necessary permissions to execute and schedule the script in the operating environment.
#
# Company: Center for AI Safety
# Author: Andriy Novykov andriy@safe.ai novykov.andriy@gmail.com
##################################################

set -u

# Global Variables
TABLE='usage_records'
START_TIME=$(date -d "-1 hour" +"%Y-%m-%d %H:00:00")
END_TIME=$(date -d "-1 hour" +"%Y-%m-%d %H:59:59")
LOG_FILE="/opt/oci-hpc/logs/billing/filesystem.log"
VERBOSE=false

# Associative arrays
declare -A TOTAL_FILESYSTEM_USAGE_PER_USER
declare -A PAID_USERS

# Log error function
log_error() {
  local message="$1"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  # Append to log file
  echo "${timestamp}: ${message}" >> "${LOG_FILE}"
}

# Log message function
log_message() {
  if [ "$VERBOSE" = true ]; then
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Append to log file
    echo "${timestamp}: ${message}" >> "${LOG_FILE}"
  fi
}

# Help function
show_help() {
cat << EOF
Usage: ${0##*/} [options]

This script collects weka filesystem usage for paid users from the Weka filesystem.
After extracting the relevant usage data, the script aggregates this information and inserts it into a MySQL database.

Options:
  -h, --help        Display this help and exit
  -v, --verbose     Enable verbose mode (log steps and errors otherwise just errors by default)

Prerequisites:
  - Bash shell environment.
  - Access to the Weka filesystem with the necessary permissions to execute the 'weka fs quota list' command.
  - MySQL client installed and network access to the MySQL database server.
  - Properly configured MySQL credentials using mysql_config_editor.
  - Necessary permisions to execute and schedule the script in the operating environment.

EOF
}

# Parse options
while [ "$#" -gt 0 ]; do
  case $1 in
    -h|--help)
      show_help
      exit
      ;;
    -v|--verbose)
      VERBOSE=true
      ;;
    --) # End of all options
      shift
      break
      ;;
    -*)
      echo "Error: Unknown option: $1" >&2
      show_help
      exit 1
      ;;
    *)  # No more options
      break
      ;;
  esac
  shift
done

#######################################
# Retrieve a list of paid users from the database.
# This function executes an SQL query to fetch user names and IDs of
# users who are not archived from the database and populates the
# PAID_USERS associative array with this data.
#
# Globals:
#   PAID_USERS - Associative array to store user names and IDs.
#   LOG_FILE   - Path to the log file.
#
# Arguments:
#   None
#
# Outputs:
#   Writes user_name and user_id to the PAID_USERS associative array.
#
# Returns:
#   Returns 0 on successful data retrieval, non-zero on SQL query failure.
#
# Usage:
#   get_paid_users_from_database
#   if [ $? -ne 0 ]; then
#     echo "Failed to retrieve paid users from the database."
#   fi
#######################################
get_paid_users_from_database() {
  log_message "Starting to retrieve paid users from the database."

  local sql="SELECT user_name, user_id FROM billing.users WHERE archived = false"
  local result

  # Execute the SQL query
  if ! result=$(mysql --login-path=billing -sN -e "$sql"); then
    log_error "Error: Failed to execute SQL query: $sql"
    return 1
  fi

  # Check if result is empty
  if [ -z "$result" ]; then
    log_error "Error: No paid users found in the database."
    return 1
  fi

  # Read the result and populate the PAID_USERS associative array
  local user_name user_id
  while read -r user_name user_id; do
    PAID_USERS["$user_name"]="$user_id"
  done <<< "$result"

  log_message "Successfully retrieved paid users from the database."
  return 0
}

#######################################
# Retrieve filesystem usage per user from the Weka filesystem.
# This function executes the Weka filesystem command to fetch usage data 
# for all users and populates the TOTAL_FILESYSTEM_USAGE_PER_USER associative 
# array with data for paid users only.
#
# Globals:
#   PAID_USERS - Associative array to check if a user is paid.
#   TOTAL_FILESYSTEM_USAGE_PER_USER - Associative array to store user IDs and their usage in bytes.
#   LOG_FILE - Path to the log file.
#
# Arguments:
#   None
#
# Outputs:
#   Writes user_id and usage in bytes to the TOTAL_FILESYSTEM_USAGE_PER_USER associative array.
#   Logs messages and errors to the LOG_FILE.
#
# Returns:
#   Returns 0 on successful data retrieval and parsing, non-zero on failure.
#
# Usage:
#   get_filesystem_usage_per_user
#   if [ $? -ne 0 ]; then
#     echo "Failed to retrieve filesystem usage per user."
#   fi
#######################################
get_filesystem_usage_per_user() {
  local usage_per_user

  if ! usage_per_user=$(weka fs quota list --all --raw-units --output path,used | sed 's/default:\///'); then
    log_error "Error: Failed to retrieve filesystem usage data. Command output: $usage_per_user"
    return 1
  fi

  # Check if empty
  if [ -z "$usage_per_user" ]; then
    log_error "Error: No filesystem usage data retrieved."
    return 1
  fi

  log_message "Parsing filesystem usage data."
  while read -r line; do
    local USER_NAME BYTES
    read -r USER_NAME BYTES <<< $(awk '{print $1, $2}' <<< "$line")
        
    # Filter for paid users only
    if [[ ${PAID_USERS[$USER_NAME]+_} ]]; then
      USER_ID=${PAID_USERS[$USER_NAME]}
      TOTAL_FILESYSTEM_USAGE_PER_USER[$USER_ID]=$BYTES
    fi
  done <<< "$usage_per_user"

  return 0
}

#######################################
# Insert filesystem usage data into the database.
# This function constructs and executes an SQL INSERT query to store the
# collected filesystem usage data for paid users in the MySQL database.
#
# Globals:
#   TOTAL_FILESYSTEM_USAGE_PER_USER - Associative array containing user IDs and their usage in bytes.
#   START_TIME - The start time for the usage data.
#   END_TIME - The end time for the usage data.
#   TABLE - The name of the database table to insert data into.
#   LOG_FILE - Path to the log file.
#
# Arguments:
#   None
#
# Outputs:
#   Inserts usage data into the database.
#   Logs messages and errors to the LOG_FILE.
#
# Returns:
#   Returns 0 on successful data insertion, non-zero on failure.
#
# Usage:
#   insert_filesystem_usage_into_db
#   if [ $? -ne 0 ]; then
#     echo "Failed to insert filesystem usage data into the database."
#   fi
#######################################
insert_filesystem_usage_into_db() {
  local sql_values=()

  for user_id in "${!TOTAL_FILESYSTEM_USAGE_PER_USER[@]}"; do
    local bytes=${TOTAL_FILESYSTEM_USAGE_PER_USER[$user_id]}
    sql_values+=("($user_id, 3, '$START_TIME', '$END_TIME', $bytes)")
  done

  # Check if we have data to insert
  if [ ${#sql_values[@]} -eq 0 ]; then
    log_error "Error: No data to insert into the database."
    return 1
  fi

  # Create SQL query
  local sql="INSERT INTO billing.$TABLE (user_id, resource_spec_id, usage_start_time, usage_end_time, usage_amount) VALUES "
  sql+=$(IFS=','; echo "${sql_values[*]}")
  sql+=";"

  log_message "Executing SQL query to insert data into $TABLE."

  if ! mysql --login-path=billing -e "$sql"; then
    log_error "Error: Failed to insert data into $TABLE"
    return 1
  fi

  return 0
}

# Main function
main() {
  log_message "Starting filesystem usage collection."

  log_message "Step 1: Attempting to retrieve paid users from database."
  if ! get_paid_users_from_database; then
    log_error "Error: Failed to retrieve paid users from the database"
    log_error "Exiting."
    exit 1
  fi
  log_message "Successfully retrieved paid users from database."

  log_message "Step 2: Attempting to retrieve filesystem usage per user."
  if ! get_filesystem_usage_per_user; then
    log_error "Error: Failed to retrieve filesystem usage per user."
    log_error "Exiting."
    exit 1
  fi
  log_message "Successfully retrived filesystem usage per user."

  log_message "Step 3: Attempting to save filesystem usage to database."
  if ! insert_filesystem_usage_into_db; then
    log_error "Error: Failed to save filesystem usage to database"
    log_error "Exiting."
    exit 1
  fi
  log_message "Successfully saved filesystem usage to database."

  log_message "Finished filesystem usage collection and storage."
}

# Start the script
main
