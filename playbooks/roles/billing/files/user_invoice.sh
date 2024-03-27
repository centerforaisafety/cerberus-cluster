#!/bin/bash

# Help function
show_help() {
cat << EOF
Usage: ${0##*/} [options]

This script generates and executes SQL queries to retrieve usage and cost information for specified resource specifications from a billing database.

Options:
  -h, --help        Display this help and exit

The script does not require any arguments for its operation. It automatically determines the account name based on the executing user's group name and retrieves billing information for that account.

Prerequisites:
  - MySQL client installed and accessible in the PATH
  - Properly configured MySQL credentials within the script

EOF
}

# Parse options
while :; do
    case $1 in
        -h|--help)
            show_help
            exit
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

# Functions
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
    DATE_FORMAT(ur.usage_start_time, '%Y-%m') AS invoice_month,
    rs.specification_name,
    rt.resource_name,
    p.price_per_unit,
    SUM(ur.usage_amount) / ${usage_divisor} AS total_usage,
    SUM(ur.usage_amount * p.price_per_unit) / ${cost_divisor} AS total_cost_per_resource_spec
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
    a.account_id, a.account_name, DATE_FORMAT(ur.usage_start_time, '%Y-%m'), rs.specification_name, rt.resource_name, p.price_per_unit
ORDER BY
    a.account_id, DATE_FORMAT(ur.usage_start_time, '%Y-%m'), rt.resource_name, rs.specification_name;
EOF
}

# MySQL credentials
DB_HOST=""
DB_USER=""
DB_PASS=""
DB_NAME=""

# Set account filter
account_name=$(id -gn)

# Check if account_name exists in the billing system.  
query="SELECT count(*) FROM billing.accounts WHERE account_name = '$account_name';"
result=$(mysql -h"$DB_HOST" -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" --silent -B -e "${query}" 2>&1 | grep -v "mysql" | sed 's/\t/,/g')
if [ "$result" = "0" ]
then
    echo "Error: Billing is not setup for the account: '$account_name'. Please contact an adminstrator."
    exit 1; 
fi

# Main code
echo 'account_id, account_name, invoice_month, spec_name, resource_name, price_per_unit, total_usage, total_cost'

# A100 Usage
# Parameters
resource_spec_id=1  
usage_divisor=3600 
cost_divisor=$usage_divisor  # Often the same as usage_divisor

query=$(generate_sql_query $resource_spec_id $usage_divisor $cost_divisor $account_name)
mysql -h"$DB_HOST" -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" --silent -B -e "${query}" 2>&1 | grep -v "mysql" | sed 's/\t/,/g'

# Network Egress Usage
# Parameters
resource_spec_id=2  
usage_divisor=1000000000 
cost_divisor=$usage_divisor  # Often the same as usage_divisor

query=$(generate_sql_query $resource_spec_id $usage_divisor $cost_divisor $account_name)
mysql -h"$DB_HOST" -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" --silent -B -e "${query}" 2>&1 | grep -v "mysql" | sed 's/\t/,/g'

# Filesystem Usage
# Parameters
resource_spec_id=3  
usage_divisor=1000000000  
cost_divisor=$usage_divisor  # Often the same as usage_divisor

query=$(generate_sql_query $resource_spec_id $usage_divisor $cost_divisor $account_name)
mysql -h"$DB_HOST" -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" --silent -B -e "${query}" 2>&1 | grep -v "mysql" | sed 's/\t/,/g'