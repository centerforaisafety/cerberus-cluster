#!/bin/bash
#
# Generate and execute SQL queries to retrieve usage and cost information from a billing database by user.
#
# Author: Andriy Novykov
# Description: This script retrieves usage and cost data for various resources per user and outputs the results in CSV format.

set -u

# Global variables
ACCOUNT_NAME="%"
readonly LOG_FILE="/opt/oci-hpc/logs/invoice_per_user.log"
VERBOSE=false

# Log error function
log_error() {
  local message="$1"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  # Append to log file
  echo "${timestamp}: ${message}" >> "${LOG_FILE}"
}

# Log message function
log_message() {
  if [ "$VERBOSE" = true ]; then
    local message="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Append to log file
    echo "${timestamp}: ${message}" >> "${LOG_FILE}"
  fi
}

# Help function
show_help() {
cat << EOF
Usage: ${0##*/} [options]

This script generates and executes SQL queries to retrieve usage and cost information from a billing database.

Options:
  -h, --help        Display this help and exit
  -v, --verbose     Enable verbose mode (log steps and errors otherwise just errors by default)
  -a, --account     Specify the account name to filter on (default: '%')

This script generates and executes SQL queries to extract usage and cost data for various resources from a billing database per user.
It supports multiple resource types including A100 Usage, Network Egress, and Filesystem Usage.
The script outputs the results in CSV format.

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
    -a|--account)
      if [ -n "$2" ]; then
        ACCOUNT_NAME="$2"
        shift
      else
        echo 'ERROR: "--account" requires a non-empty option argument.'
        exit 1
      fi
      ;;
    -v|--verbose)
      VERBOSE=true
      ;;
    --) # End of all options
      shift
      break
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

# Function to generate invoice sql query per user
generate_sql_query() {
    local resource_spec_id="$1"
    local usage_divisor="$2"
    local cost_divisor="$3"
    local account_name="$4"

    # Generate the SQL query using the provided arguments
    cat <<EOF
SELECT
    a.account_id,
    a.account_name,
    u.user_id,
    u.user_name,
    DATE_FORMAT(ur.usage_start_time, '%Y-%m') AS invoice_month,
    rs.specification_name,
    rt.resource_name,
    p.price_per_unit,
    SUM(ur.usage_amount) / ${usage_divisor} AS total_usage,
    SUM(ur.usage_amount * p.price_per_unit) / ${cost_divisor} AS total_cost_per_user
FROM
    billing.accounts a
JOIN
    billing.users u ON a.account_id = u.account_id
JOIN
    billing.usage_records ur ON u.user_id = ur.user_id
JOIN
    billing.resource_specifications rs ON ur.resource_spec_id = rs.resource_spec_id
JOIN
    billing.resource_types rt ON rs.resource_type_id = rt.resource_type_id
JOIN
    billing.pricing p ON a.account_id = p.account_id AND rs.resource_spec_id = p.resource_spec_id
WHERE
    p.price_effective_date <= ur.usage_start_time
    AND (p.price_end_date IS NULL OR p.price_end_date >= ur.usage_end_time)
    AND rs.resource_spec_id = ${resource_spec_id}
    AND a.account_name LIKE '${account_name}'
    AND a.archived = FALSE
GROUP BY
    a.account_id, a.account_name, u.user_id, u.user_name, DATE_FORMAT(ur.usage_start_time, '%Y-%m'), rs.specification_name, rt.resource_name, p.price_per_unit
ORDER BY
    a.account_id, u.user_id, DATE_FORMAT(ur.usage_start_time, '%Y-%m'), rt.resource_name, rs.specification_name;
EOF
}

# Main function
main() {
  log_message "Processing invoices by user."

  echo "account_id, account_name, user_id, user_name, invoice_month, spec_name, resource_name, price_per_unit, total_usage, total_cost"

  # A100 Usage
  # Parameters
  log_message "Processing A100 usage."
  resource_spec_id=1
  usage_divisor=3600
  cost_divisor=$usage_divisor

  query=$(generate_sql_query "$resource_spec_id" "$usage_divisor" "$cost_divisor" "$ACCOUNT_NAME")
  result=$(mysql --defaults-extra-file=/home/ubuntu/.billing.cnf --silent -B -e "${query}")
  if [ $? -ne 0 ]; then
    log_error "Error: Failed to process A100 usage."
    log_error "Exiting."
    exit 1
  fi
  echo "${result//	/,}"
  log_message "Successfully processed A100 usage."

  # Network Egress Usage
  # Parameters
  log_message "Processing network egress usage."
  resource_spec_id=2
  usage_divisor="$((10**9))"  # 1 billion
  cost_divisor=$usage_divisor

  query=$(generate_sql_query "$resource_spec_id" "$usage_divisor" "$cost_divisor" "$ACCOUNT_NAME")
  result=$(mysql --defaults-extra-file=/home/ubuntu/.billing.cnf --silent -B -e "${query}")
  if [ $? -ne 0 ]; then
    log_error "Error: Failed to process network egress usage."
    log_error "Exiting."
    exit 1
  fi
  echo "${result//	/,}"
  log_message "Successfully processed network egress usage."

  # Filesystem Usage
  # Parameters
  log_message "Processing filesystem usage."
  resource_spec_id=3
  usage_divisor="$((10**9))"  # 1 billion
  cost_divisor=$usage_divisor

  query=$(generate_sql_query "$resource_spec_id" "$usage_divisor" "$cost_divisor" "$ACCOUNT_NAME")
  result=$(mysql --defaults-extra-file=/home/ubuntu/.billing.cnf --silent -B -e "${query}")
  if [ $? -ne 0 ]; then
    log_error "Error: Failed to process filesystem usage."
    log_error "Exiting."
    exit 1
  fi
  echo "${result//	/,}"
  log_message "Successfully processed filesystem usage."

  log_message "Successfully processed invoices by user."
}

main
