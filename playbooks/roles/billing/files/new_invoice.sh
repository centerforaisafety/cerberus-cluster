#!/bin/bash

# Functions
generate_sql_query() {
    local resource_spec_id="$1"
    local usage_divisor="$2"
    local cost_divisor="$3"

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
    AND a.archived = FALSE
GROUP BY
    a.account_id, a.account_name, DATE_FORMAT(ur.usage_start_time, '%Y-%m'), rs.specification_name, rt.resource_name, p.price_per_unit
ORDER BY
    a.account_id, DATE_FORMAT(ur.usage_start_time, '%Y-%m'), rt.resource_name, rs.specification_name;
EOF
}

# Your MySQL credentials
DB_HOST="172.16.7.207"
DB_USER="opc"
DB_PASS="Billing1234!"
DB_NAME="billing"

# Execute the query
mysql -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" -e "${QUERY}"

# Main code
echo 'account_id, account_name, invoice_month, spec_name, resource_name, price_per_unit, total_usage, total_cost'

# A100 
# Parameters
resource_spec_id=1  # Example value; adjust as needed
usage_divisor=3600  # Example value for A100; adjust based on resource
cost_divisor=$usage_divisor  # Often the same as usage_divisor

query=$(generate_sql_query $resource_spec_id $usage_divisor $cost_divisor)
mysql -h"$DB_HOST" -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" -e "${query}"