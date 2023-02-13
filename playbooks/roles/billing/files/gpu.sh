#!/bin/bash

#################################
# Description:
#   This script calculates and records the daily usage of GPU resources by paid users. 
#   It retrieves usage data, distinguishes between different GPU types (A100 and H100), 
#   and inserts summarized data into a database for billing purposes.
#
# Usage:
#   - This script should be scheduled to run daily at 00:00:00 with a cron job.
#     - Example cron job: 0 0 * * * /opt/oci-hpc/billing/collect_gpu_usage.sh
#
# Company: Center for AI Safety
# Author: Andriy Novykov andriy@safe.ai novykov.andriy@gmail.com
#################################

set -u

# Global Variables
readonly PARTITION="compute"
readonly TABLE="usage_records"
readonly DATE=$(date -d "-1 day" +"%Y-%m-%d")
readonly LOG_FILE="/opt/oci-hpc/logs/billing/gpu.log"
VERBOSE=false

# Associative arrays for each gpu type
declare -A TOTAL_A100_USAGE_PER_USER
declare -A TOTAL_H100_USAGE_PER_USER

# Associative array of paid users
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

This script calculates and records the daily usage of GPU resources by paid users.
It retrieves usage data, distinguishes between different GPU types (A100 and H100),
and inserts summarized data into a database for billing purposes.

Options:
  -h, --help        Display this help and exit
  -v, --verbose     Enable verbose mode (log steps and errors otherwise just errors by default)

Prerequisites:
  - MySQL client installed and accessible in the PATH
  - Properly configured MySQL credentials using mysql_config_editor

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
# Convert time duration from HH:MM:SS format to seconds.
# This function takes a time duration string in HH:MM:SS format and
# converts it to the total number of seconds.
#
# Globals:
#   LOG_FILE - Path to the log file.
#
# Arguments:
#   $1 - Time duration string in HH:MM:SS format.
#
# Outputs:
#   Prints the total number of seconds.
#
# Returns:
#   Returns 0 on successful conversion, non-zero on invalid input format.
#
# Usage:
#   seconds=$(convert_to_seconds "01:23:45")
#   if [ $? -ne 0 ]; then
#     echo "Invalid time format."
#   fi
#######################################
convert_to_seconds() {
  log_message "Starting conversion of time string to seconds: $1"

  local elapsed_time=$1
  local days=0
  local hours=0
  local minutes=0
  local seconds=0

  # Check if days are present in the time format
  if [[ $elapsed_time == *-* ]]; then
      days=${elapsed_time%%-*}
      elapsed_time=${elapsed_time#*-}
  fi

  # Split the time into hours, minutes, and seconds
  IFS=':' read -ra time_parts <<< "$elapsed_time"
  hours=$((10#${time_parts[0]}))
  minutes=$((10#${time_parts[1]}))
  seconds=$((10#${time_parts[2]}))

  # Calculate total seconds
  total_seconds=$((days * 86400 + hours * 3600 + minutes * 60 + seconds))
  echo "$total_seconds"
  log_message "Converted $1 to $total_seconds seconds"
  return 0
}

#######################################
# Extract the GPU type from a resource allocation string.
# This function takes a resource allocation string, which includes
# GPU details, and extracts the GPU type (e.g., A100, H100).
#
# Globals:
#   LOG_FILE - Path to the log file.
#
# Arguments:
#   $1 - Resource allocation string.
#
# Outputs:
#   Prints the GPU type (a100, h100).
#
# Returns:
#   Returns 0 on successful extraction, non-zero on failure.
#
# Usage:
#   gpu_type=$(extract_gpu_type "gpu:A100:4")
#   if [ $? -ne 0 ]; then
#     echo "Failed to extract GPU type."
#   fi
#######################################
extract_gpu_type() {
  log_message "Starting extraction of GPU type from allocation string: $alloc_tres"
  local gpu_type

  if ! gpu_type=$(echo "$1" | grep -o 'gres/gpu:[^,]*' | cut -d ':' -f2 | cut -d '=' -f1); then
    log_error "Error: Failed to extract GPU type from allocation string: $alloc_tres"
    return 1
  fi

  log_message "Extracted GPU type: $gpu_type"
  echo "$gpu_type"
  return 0
}

#######################################
# Extract the GPU quantity from a resource allocation string.
# This function takes a resource allocation string that includes
# details about the GPU allocation and extracts the number of GPUs
# allocated.
#
# Globals:
#   LOG_FILE - Path to the log file.
#
# Arguments:
#   $1 - Resource allocation string (e.g., "gpu:A100:4").
#
# Outputs:
#   Prints the number of GPUs allocated.
#
# Returns:
#   Returns 0 on successful extraction, non-zero on failure.
#
# Usage:
#   gpu_quantity=$(extract_gpu_quantity "gpu:A100:4")
#   if [ $? -ne 0 ]; then
#     echo "Failed to extract GPU quantity."
#   fi
#######################################
extract_gpu_quantity() {
  log_message "Starting extraction of GPU quantity from allocation string: $alloc_tres"
  gpu_quantity=""

  # Extract the string that contains 'gres/gpu:'
  gpu_info=$(echo "$1" | grep -o 'gres/gpu:[^,]*')

  if [ -n "$gpu_info" ]; then
    # Extract the quantity
    if ! gpu_quantity=$(echo "$gpu_info" | cut -d '=' -f2); then
      log_error "Error: Failed to extract GPU quantity from allocation string: $alloc_tres"
      return 1
    fi
  fi

  log_message "Extraced GPU quantity: $gpu_quantity"
  echo "$gpu_quantity"
  return 0
}

#######################################
# Retrieve and process GPU usage per user.
# This function fetches GPU usage data from a source, processes the data
# to calculate total usage per user for different GPU types (A100, H100),
# and updates global associative arrays with this information.
#
# Globals:
#   PAID_USERS - Associative array of paid users (user_name to user_id).
#   TOTAL_A100_USAGE_PER_USER - Associative array of total A100 GPU usage per user.
#   TOTAL_H100_USAGE_PER_USER - Associative array of total H100 GPU usage per user.
#   LOG_FILE - Path to the log file.
#
# Arguments:
#   None
#
# Outputs:
#   Updates TOTAL_A100_USAGE_PER_USER and TOTAL_H100_USAGE_PER_USER with GPU usage data.
#
# Returns:
#   Returns 0 on successful processing, non-zero on failure.
#
# Usage:
#   get_gpu_usage_per_user
#   if [ $? -ne 0 ]; then
#     echo "Failed to retrieve and process GPU usage data."
#   fi
#######################################
get_gpu_usage_per_user() {
  local usage_per_user
  if ! usage_per_user=$(sacct -a -X --partition $PARTITION --format=user,elapsed,AllocTRES --starttime ${DATE}T00:00:00 --endtime ${DATE}T23:59:59 --state=bf,ca,cd,dl,f,nf,oom,pr,to --parsable2); then
    log_error "Error: Failed to fetch GPU usage data."
    return 1
  fi

  # Process each line of the fetched data
  while read -r line; do
      local user_name elapsed_time alloc_tres
      read -r user_name elapsed_time alloc_tres <<< $(awk -F '|' '{print $1, $2, $3}' <<< "$line")
      log_message "Processing data for user: $user_name, elapsed time: $elapsed_time, allocation: $alloc_tres"

      # Filter for paid users only
      if [[ ${PAID_USERS[$user_name]+_} ]]; then
        local user_id
        local seconds
        local gpu_type
        local gpu_quantity

        user_id=${PAID_USERS[$user_name]}

        if ! seconds=$(convert_to_seconds "$elapsed_time"); then
          log_error "Error: Failed to convert elapsed time to seconds for user: $user_name, elapsed time: $elapsed_time"
          return 1
        fi
  
        if ! gpu_type=$(extract_gpu_type "$alloc_tres"); then
          log_error "Error: Failed to extract GPU type from allocation string: $alloc_tres"
          return 1
        fi
  
        if ! gpu_quantity=$(extract_gpu_quantity "$alloc_tres"); then
          log_error "Error: Failed to extract GPU quantity from allocation string: $alloc_tres"
          return 1
        fi

        # Filter by gpu type
        if [[ "$gpu_type" == "a100" ]]; then
          TOTAL_A100_USAGE_PER_USER[$user_id]=$((TOTAL_A100_USAGE_PER_USER[$user_id] + $(($seconds * $gpu_quantity))))
          log_message "Updated A100 usage for user_id: $user_id, total usage: ${TOTAL_A100_USAGE_PER_USER[$user_id]}"
        elif [[ "$gpu_type" == "h100" ]]; then
          TOTAL_H100_USAGE_PER_USER[$user_id]=$((TOTAL_H100_USAGE_PER_USER[$user_id] + $(($seconds * $gpu_quantity))))
          log_message "Updated H100 usage for user_id: $user_id, total usage: ${TOTAL_H100_USAGE_PER_USER[$user_id]}"
        fi
      fi
  done <<< "$usage_per_user"

  log_message "Successfully processed GPU usage per user."
  return 0
}

#######################################
# Insert GPU usage data into the database.
# This function constructs and executes an SQL INSERT statement to record
# the GPU usage data into the database for billing purposes.
#
# Globals:
#   TOTAL_A100_USAGE_PER_USER - Associative array of total A100 GPU usage per user.
#   TOTAL_H100_USAGE_PER_USER - Associative array of total H100 GPU usage per user.
#   DATE - The date for which usage is being recorded.
#   TABLE - The name of the database table where usage records are inserted.
#   LOG_FILE - Path to the log file.
#
# Arguments:
#   None
#
# Outputs:
#   Inserts data into the database and logs the operation.
#
# Returns:
#   Returns 0 on successful insertion, non-zero on failure.
#
# Usage:
#   insert_gpu_usage_into_db
#   if [ $? -ne 0 ]; then
#     echo "Failed to insert GPU usage data into the database."
#   fi
#######################################
save_gpu_usage_to_database() {
  log_message "Starting insertion of GPU usage data into the database"

  local sql_values=()
  local user_id total_seconds

  # Append INSERT statements for A100 usage records
  for user_id in "${!TOTAL_A100_USAGE_PER_USER[@]}"; do
    total_seconds="${TOTAL_A100_USAGE_PER_USER[$user_id]}"
    sql_values+=("($user_id, 1, '${DATE} 00:00:00', '${DATE} 23:59:59', $total_seconds)")
  done

  # Append INSERT statements for H100 usage records
  for user_id in "${!TOTAL_H100_USAGE_PER_USER[@]}"; do
    total_seconds="${TOTAL_H100_USAGE_PER_USER[$user_id]}"
    sql_values+=("($user_id, 4, '${DATE} 00:00:00', '${DATE} 23:59:59', $total_seconds)")
  done

  # Check if there are values to insert
  if [ ${#sql_values[@]} -eq 0 ]; then
    log_error "Error: No GPU usage data to insert into the database"
    return 1
  fi

  local sql="INSERT INTO billing.$TABLE (user_id, resource_spec_id, usage_start_time, usage_end_time, usage_amount) VALUES "
  sql+=$(IFS=','; echo "${sql_values[*]}")
  sql+=";"

  # Execute the SQL query and capture result
  if ! mysql --login-path=billing -e "$sql"; then
    log_error "Error: Failed to insert data into $TABLE"
    return 1
  fi

  log_message "Successfully inserted GPU usage data into the database"
  return 0
}

#######################################
# Main function to coordinate the retrieval and insertion of GPU usage data.
# This function orchestrates the process of fetching paid users, retrieving GPU usage data,
# and inserting the usage data into the database.
#
# Globals:
#   LOG_FILE - Path to the log file.
#
# Arguments:
#   None
#
# Outputs:
#   Logs the progress and results of each step to the log file.
#
# Returns:
#   Returns 0 on success, exit on failure.
#######################################
main() {
  log_message "Starting GPU usage billing process"

  log_message "Step 1: Retrieving paid users from the database"
  if ! get_paid_users_from_database; then
    log_error "Error: Failed to retrieve paid users from the database"
    log_error "Exiting."
    exit 1
  fi
  log_message "Successfully retrieved paid users"

  log_message "Step 2: Retrieving GPU usage per user"
  if ! get_gpu_usage_per_user; then
    log_error "Error: Failed to retrieve GPU usage data per user."
    log_error "Exiting."
    exit 1
  fi
  log_message "Successfully retrieved GPU usage data per user"

  log_message "Step 3: Inserting GPU usage data into the database"
  if ! save_gpu_usage_to_database; then
    log_error "Error: Failed to insert GPU usage data into the database"
    log_error "Exiting."
    exit 1
  fi
  log_message "Successfully inserted GPU usage data into the database"

  log_message "Completed GPU usage billing process"
  return 0
}

main
