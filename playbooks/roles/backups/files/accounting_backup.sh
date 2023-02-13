#!/usr/bin/env bash

# This script automates the accounting backup process, including:
# - Extracting database information using `mysqldump`.
# - Compressing the backup file.
# - Uploading the backup to Object Storage using `oci` CLI.
#
# Logs are written to /opt/oci-hpc/logs/backups/accounting_backup.log
#
# Dependencies:
# - bash
# - mysqldump
# - gzip
# - oci CLI

LOG_FILE="/opt/oci-hpc/logs/backups/backup_accounting.log"
mkdir -p "$(dirname "$LOG_FILE")"
exec >> "$LOG_FILE" 2>&1

timestamp=$(date '+%Y_%m_%d')
backup_name="accounting_backup_${timestamp}.sql"
db_backup_path="/tmp/$backup_name"
mysql_credentials="/home/ubuntu/.billing.cnf"

echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO - Starting accounting database backup process."

dump_cmd="/usr/bin/mysqldump --defaults-extra-file=${mysql_credentials} --single-transaction -B billing --result-file=${db_backup_path}"
gzip_db_cmd="gzip -f ${db_backup_path}"
oci_db_cmd="oci os object put --force --bucket-name backups --name '/accounting/${backup_name}.gz' --file ${db_backup_path}.gz"
remove_db_cmd="rm ${db_backup_path}.gz"

run_command() {
    local cmd="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO - Running command: $cmd"
    if ! output=$(eval "$cmd" 2>&1); then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR - Command '$cmd' failed with error: $output"
        exit 1
    fi
}

# Backup accounting database
run_command "$dump_cmd"
run_command "$gzip_db_cmd"
run_command "$oci_db_cmd"
run_command "$remove_db_cmd"

echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO - Completed accounting database backup process successfully."