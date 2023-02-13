#!/bin/bash

#######################################################
# Description:
#   This script records network egress traffic usage by users across multiple hosts.
#   It gathers network usage data from each host, aggregates the data by user, and then stores this
#   information in a database for billing and tracking purposes. The script is tailored for an environment
#   with Slurm Workload Manager, iptables, SSH, and MySQL.
#
# Features:
#   - Gathers network usage data from hosts listed by Slurm Workload Manager.
#   - Processes and aggregates network usage data by user ID.
#
# Usage:
#   - This script should be scheduled to run hourly with a cron job.
#     - Example cron job: 0 * * * * /opt/oci-hpc/billing/network.sh
#
# Requirements:
#   - Slurm Workload Manager: for fetching the list of hosts.
#   - iptables: for gathering network usage statistics.
#   - SSH: for remote execution of commands on listed hosts.
#   - MySQL client installed and accessible in the PATH.
#   - Properly configured MySQL credentials using mysql_config_editor
#
#######################################################
set -u

# Global variables
# Gather list of hosts from Slurm
readonly TABLE='usage_records'
readonly START_TIME=$(date -d "-1 hour" +"%Y-%m-%d %H:00:00")
readonly END_TIME=$(date -d "-1 hour" +"%Y-%m-%d %H:59:59")
readonly LOG_FILE="/opt/oci-hpc/logs/billing/network.log"
VERBOSE=false

# Associative array
declare -A TOTAL_NETWORK_USAGE_PER_USER

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

This script records network egress traffic usage by users across multiple hosts.
It gathers network usage data from each host, aggregates the data by user, and then stores this
information in a database for billing and tracking purposes. The script is tailored for an environment
with Slurm Workload Manager, iptables, SSH, and MySQL.

Options:
  -h, --help        Display this help and exit
  -v, --verbose     Enable verbose mode (log steps and errors otherwise just errors by default)

Prerequisites:
  - Slurm Workload Manager: for fetching the list of hosts.
  - iptables: for gathering network usage statistics.
  - SSH: for remote execution for commands on listed hosts.
  - MySQL client installed and accessible in the PATH.
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
# Retrieve network usage per user from a specified host.
# This function connects to a given host via SSH, executes commands to fetch 
# network traffic data filtered by user, and then resets the usage counters.
# It uses the global array to accumulate data and logs the operations.
#
# Globals:
#   TOTAL_NETWORK_USAGE_PER_USER - Associative array to store accumulated network
#                                  usage data per user. Updated with data fetched.
#   LOG_FILE - Path to the log file for logging operation status.
#
# Arguments:
#   host - The hostname of the server from which to fetch network usage data.
#
# Outputs:
#   Updates the TOTAL_NETWORK_USAGE_PER_USER associative array with the network
#   usage data fetched from the specified host.
#   Logs messages to LOG_FILE detailing the outcome of the operations.
#
# Returns:
#   Returns 0 if the network usage data is successfully retrieved and processed,
#   1 if any errors occur during SSH connection or command execution.
#
# Usage:
#   get_network_usage_per_user "server01"
#   if [ $? -ne 0 ]; then
#     echo "Failed to retrieve network usage data from the host."
#   fi
#######################################
get_network_usage_per_user() {
  log_message "Starting to retrieve network usage per user."

  local host=$1
  # Validate host
  if [[ -z "$host" ]]; then
    log_return "No host specified for getting network usage."
    return 1
  fi

  local iptable_cmd='sudo iptables -L USER_TRAFFIC -v -x -n | awk '\''NR>3 && /MARK set/ {print $2, $13}'\'' && sudo iptables -Z USER_TRAFFIC'
  local result
  result=$(ssh "$host" "$iptable_cmd")
 
  # Error handling
  if [ $? -ne 0 ]; then
    log_error "Error: Failed to execute SSH command on host $host with status $?"
    return 1
  fi
 
  echo "$result"
  log_message "Successfully retrieved network usage for host $host."
  return 0
}

#######################################
# Process network usage data.
# This function reads through the network usage data provided as a parameter,
# extracts relevant details (user ID and bytes used), and updates the
# TOTAL_NETWORK_USAGE_PER_USER associative array. It also performs data validation
# and logs any errors encountered during processing.
#
# Globals:
#   TOTAL_NETWORK_USAGE_PER_USER - Associative array to store accumulated network
#                                  usage data per user.
#   LOG_FILE - Path to the log file for logging operation status.
#
# Arguments:
#   usage_data - A string containing raw network usage data, typically multiple
#                lines with each line containing a user ID and the amount of data
#                used by that user.
#
# Outputs:
#   Updates the TOTAL_NETWORK_USAGE_PER_USER associative array with the sum of
#   bytes used by each user.
#   Logs messages to LOG_FILE detailing any errors encountered during processing.
#
# Returns:
#   Returns 0 if all data is processed successfully, 1 if any errors occur.
#
# Usage:
#   process_network_usage "$raw_data"
#   if [ $? -ne 0 ]; then
#     echo "Error processing network usage data."
#   fi
#######################################
process_network_usage() {
  log_message "Starting to process network usage."

  local usage_data=$1
  local line bytes user_id

  if [[ -z "$usage_data" ]]; then
    log_error "Error: Received empty usage data for processing."
    return 1
  fi

  while read -r line; do
    if ! read -r bytes user_id <<< $(awk '{print $1, $2}' <<< "$line"); then
      log_error "Error: Failed to parse line: $line"
      return 1
    fi

    # Validate data
    if [[ ! "$bytes" =~ ^[0-9]+$ ]] || [[ -z "$user_id" ]]; then
      log_error "Error: Invalid data: bytes='$bytes', user_id='$user_id'"
      return 1
    fi

    # Update total usage
    TOTAL_NETWORK_USAGE_PER_USER[$user_id]=$(( ${TOTAL_NETWORK_USAGE_PER_USER[$user_id]:-0} + bytes ))
    log_message "Updated user $user_id with $bytes bytes."
  done <<< "$usage_data"

  log_message "Finished processing network usage."
}

#######################################
# Save network usage data to the database.
# This function constructs an SQL query from the TOTAL_NETWORK_USAGE_PER_USER
# associative array to insert data into the specified database table. It executes
# this SQL query using the 'mysql' command-line tool, logs the operation, and
# handles any errors that occur.
#
# Globals:
#   TOTAL_NETWORK_USAGE_PER_USER - Associative array containing user_ids as keys
#                                  and network usage data as values.
#   TABLE - Name of the database table where data is to be inserted.
#   LOG_FILE - Path to the log file for logging operation status.
#
# Arguments:
#   None
#
# Outputs:
#   Writes network usage data to the database.
#   Logs messages to LOG_FILE detailing the outcome of the operation.
#
# Returns:
#   Returns 0 on successful data insertion, 1 on failure.
#
# Usage:
#   save_network_usage_to_database
#   if [ $? -ne 0 ]; then
#     echo "Failed to save data to the database."
#   fi
#######################################
save_network_usage_to_database() {
  log_message "Attempting to save network usage to database."

  local sql_values=()
  local user_id bytes

  # Check if there's data to process
  if [ ${#TOTAL_NETWORK_USAGE_PER_USER[@]} -eq 0 ]; then
    log_error "Error: No data to insert into the database."
    return 1
  fi

  # Prepare SQL values
  for user_id in "${!TOTAL_NETWORK_USAGE_PER_USER[@]}"; do
    bytes=${TOTAL_NETWORK_USAGE_PER_USER[$user_id]}
    sql_values+=("(${user_id}, 2, '${START_TIME}', '${END_TIME}', ${bytes})")
  done

  # Construct SQL query
  local sql="INSERT INTO billing.$TABLE (user_id, resource_spec_id, usage_start_time, usage_end_time, usage_amount) VALUES "
  sql+=$(IFS=','; echo "${sql_values[*]}")
  sql+=";"

  # Execute query and handle errors 
  if ! mysql --defaults-extra-file=/home/ubuntu/.billing.cnf -e "$sql"; then
    log_error "Error: Failed to insert data into $TABLE: $result"
    return 1
  fi

  log_message "Succesfully saved network usage into $TABLE."
}

#######################################
# Main function to orchestrate the network usage data collection process.
# This function initiates by logging the start of the data collection, retrieves
# a list of hosts from the Slurm Workload Manager, and iterates over each host to
# collect and process network usage data. It handles errors at each critical step,
# logs appropriate messages for actions and errors, and finally, saves the processed
# data to a database. The function concludes by logging the completion of the process.
#
# Globals:
#   TOTAL_NETWORK_USAGE_PER_USER - Associative array updated with network usage data per user.
#   LOG_FILE - Path to the log file where operation logs are stored.
#
# Arguments:
#   None
#
# Outputs:
#   Logs various operational messages and errors to LOG_FILE.
#   Updates the TOTAL_NETWORK_USAGE_PER_USER associative array.
#
# Returns:
#   Returns 0 on successful completion of all operations, 1 if any critical operation fails.
#
# Usage:
#   main
#   if [ $? -ne 0 ]; then
#     echo "Network data collection process encountered an error."
#   fi
#######################################
main() {
  log_message "Starting network usage data collection."  

  local -r hosts=$(sudo sinfo -S "%n" -o "%n" | tail -n +2)

  # Check if the hosts string is empty
  if [ -z "$hosts" ]; then
    log_error "Error: No hosts provided for processing. Exiting."
    exit 1
  fi

  # Iterate over each host to gather network usage data. If we have data then process it. 
  for host in ${hosts[@]}; do
    log_message "Collecting data from host: $host"
    usage_per_user=$(get_network_usage_per_user "$host")
   
    # Error handling
    if [ $? -ne 0 ]; then
      log_error "Error: Failed to retrieve network usage data from host $host."
      continue
    fi
 
    # Check if the result is empty
    if [ -z "$usage_per_user" ]; then
      log_error "Error: No data received from host: $host"
      continue 
    fi

    log_message "Processing data for host: $host"
    if ! process_network_usage "$usage_per_user"; then
      log_error "Error: Failed to process data for host: $host"
      log_error "Exiting."
      continue
    fi
  done
  
  log_message "Saving accumulated network usage data to the database."  
  if ! save_network_usage_to_database; then
    log_error "Error: Failed to save accumulated network usage data into the database"
    log_error "Exiting."
    exit 1
  fi

  log_message "Data collection and storage complete."
} 

# Start the script
main
