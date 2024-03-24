#!/usr/bin/python3

import mysql.connector

# Functions
def find_and_cut(filename, search_string, delimiter):
    with open(filename, 'r') as file:
        for line in file:
            if search_string in line:
                parts = line.split(delimiter)
                if len(parts) > 1:
                    return parts[1].strip()

def execute(query, arguments = None):
    # Establishing a connection to the database
    try:
        connection = mysql.connector.connect(
            host=host,
            user=user,
            password=password,
            database=database
        )

        # Create a cursor object to execute queries
        cursor = connection.cursor()

        # Execute query
        if (arguments is None):
            cursor.execute(query)
        else:
            cursor.execute(query, arguments)

        # Fetch the results
        results = cursor.fetchall()
        
        # Close the cursor and connection
        cursor.close()
        connection.close()

        return results

    except mysql.connector.Error as error:
        print(f"Failed to connect to MySQL: {error}")
     
# MySQL connection details
host = find_and_cut('/etc/ansible/hosts', 'billing_mysql_ip', '=')  # Host where the database server is located
user = find_and_cut('/etc/ansible/hosts', 'billing_mysql_db_admin_username', '=')  # Username to log in as
password = find_and_cut('/etc/ansible/hosts', 'billing_mysql_db_admin_password', '=')  # Password for the user
database = 'billing'  # Database name to connect to

# SQL queries
a100_sql = """
SELECT 
    a.account_id,
    a.account_name,
    DATE_FORMAT(ur.usage_start_time, '%Y-%m') AS invoice_month,
    rs.specification_name,
    rt.resource_name,
    p.price_per_unit,
    SUM(ur.usage_amount) / 3600 AS total_usage,
    SUM(ur.usage_amount * p.price_per_unit) / 3600 AS total_cost_per_resource_spec
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
    AND rs.resource_spec_id = 1
    AND a.archived = FALSE
GROUP BY 
    a.account_id, a.account_name, DATE_FORMAT(ur.usage_start_time, '%Y-%m'), rs.specification_name, rt.resource_name, p.price_per_unit
ORDER BY 
    a.account_id, DATE_FORMAT(ur.usage_start_time, '%Y-%m'), rt.resource_name, rs.specification_name;
"""

network_sql = """
SELECT
    a.account_id,
    a.account_name,
    DATE_FORMAT(ur.usage_start_time, '%Y-%m') AS invoice_month,
    rs.specification_name,
    rt.resource_name,
    p.price_per_unit,
    SUM(ur.usage_amount) / 1000000000 AS total_usage,
    SUM(ur.usage_amount * p.price_per_unit) / 1000000000 AS total_cost_per_resource_spec
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
    AND rs.resource_spec_id = 2
    AND a.archived = FALSE
GROUP BY
    a.account_id, a.account_name, DATE_FORMAT(ur.usage_start_time, '%Y-%m'), rs.specification_name, rt.resource_name, p.price_per_unit
ORDER BY
    a.account_id, DATE_FORMAT(ur.usage_start_time, '%Y-%m'), rt.resource_name, rs.specification_name;
"""

weka_sql = """
SELECT
    a.account_id,
    a.account_name,
    DATE_FORMAT(ur.usage_start_time, '%Y-%m') AS invoice_month,
    rs.specification_name,
    rt.resource_name,
    p.price_per_unit,
    SUM(ur.usage_amount) / 1000000000 AS total_usage,
    SUM(ur.usage_amount * p.price_per_unit) / 1000000000 AS total_cost_per_resource_spec
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
    AND rs.resource_spec_id = 3
    AND a.archived = FALSE
GROUP BY
    a.account_id, a.account_name, DATE_FORMAT(ur.usage_start_time, '%Y-%m'), rs.specification_name, rt.resource_name, p.price_per_unit
ORDER BY
    a.account_id, DATE_FORMAT(ur.usage_start_time, '%Y-%m'), rt.resource_name, rs.specification_name;
"""

# Main code

# a100
print("account_id, account_name, invoice_month, spec_name, resource_name, price_per_unit, total_usage, total_cost")

results = execute(a100_sql)

for (account_id, account_name, invoice_month, spec_name, resource_name, price_per_unit, total_usage, total_cost) in results:
  print("{}, {}, {}, {}, {}, ${}, {}, ${}".format(
    account_id, account_name, invoice_month, spec_name, resource_name, price_per_unit, total_usage, total_cost))

# network

results = execute(network_sql)

for (account_id, account_name, invoice_month, spec_name, resource_name, price_per_unit, total_usage, total_cost) in results:
  print("{}, {}, {}, {}, {}, ${}, {}, ${}".format(
    account_id, account_name, invoice_month, spec_name, resource_name, price_per_unit, total_usage, total_cost))

# weka
results = execute(weka_sql)

for (account_id, account_name, invoice_month, spec_name, resource_name, price_per_unit, total_usage, total_cost) in results:
  print("{}, {}, {}, {}, {}, ${}, {}, ${}".format(
    account_id, account_name, invoice_month, spec_name, resource_name, price_per_unit, total_usage, total_cost))
