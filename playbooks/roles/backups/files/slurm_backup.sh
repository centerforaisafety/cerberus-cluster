#!/usr/bin/env bash

# This script automates the Slurm backup process, including:
# - Extracting database information using `mysqldump`.
# - Compressing the backup file.
# - Uploading the backup to Object Storage using `oci` CLI.
#
# Logs are written to /opt/oci-hpc/logs/backups/backup_slurm.log
#
# Dependencies:
# - bash
# - mysqldump
# - gzip
# - oci CLI

LOG_FILE="/opt/oci-hpc/logs/backups/backup_slurm.log"
mkdir -p "$(dirname "$LOG_FILE")"
exec >> "$LOG_FILE" 2>&1

timestamp=$(date '+%Y_%m_%d')
db_backup_name="slurm_backup_${timestamp}.sql"
db_backup_path="/tmp/${db_backup_name}"
config_backup_name="slurm_${timestamp}.conf"
config_backup_path="/tmp/${config_backup_name}"
mysql_credentials="/home/ubuntu/.slurm.cnf"

echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO - Starting Slurm database backup process."

dump_cmd="/usr/bin/mysqldump --defaults-extra-file=${mysql_credentials} --single-transaction -B slurm_accounting --result-file=${db_backup_path}"
gzip_db_cmd="gzip -f ${db_backup_path}"
oci_db_cmd="oci os object put --force --bucket-name backups --name '/slurm/${db_backup_name}.gz' --file ${db_backup_path}.gz"
remove_db_cmd="rm ${db_backup_path}.gz"

cp_cmd="cp /etc/slurm/slurm.conf ${config_backup_path}"
gzip_conf_cmd="gzip -f ${config_backup_path}"
oci_conf_cmd="oci os object put --force --bucket-name backups --name '/slurm/${config_backup_name}.gz' --file ${config_backup_path}.gz"
remove_conf_cmd="rm ${config_backup_path}.gz"

run_command() {
    local cmd="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO - Running command: $cmd"
    if ! output=$(eval "$cmd" 2>&1); then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR - Command '$cmd' failed with error: $output"
        exit 1
    fi
}

# Backup Slurm database
run_command "$dump_cmd"
run_command "$gzip_db_cmd"
run_command "$oci_db_cmd"
run_command "$remove_db_cmd"

# Backup Slurm configuration
run_command "$cp_cmd"
run_command "$gzip_conf_cmd"
run_command "$oci_conf_cmd"
run_command "$remove_conf_cmd"

echo "$(date '+%Y-%m-%d %H:%M:%S') - INFO - Completed Slurm database backup process successfully."