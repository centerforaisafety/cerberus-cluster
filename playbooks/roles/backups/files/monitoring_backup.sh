#!/bin/bash

# --- Configuration -------------------------------------------------
LOG_FILE="/opt/oci-hpc/logs/backups/monitoring_backup.log"
CREDENTIALS_FILE="/etc/credentials"

VM_BACKUP_CMD=(
  "/usr/bin/vmbackup"
  "-storageDataPath=/home/ubuntu/utils/victoria_metrics/data/"
  "-snapshot.createURL=http://localhost:8428/snapshot/create"
  "-credsFilePath=$CREDENTIALS_FILE"
  "-dst=s3://backups/victoria_metrics"
  "-customS3Endpoint=axvscsfozusv.compat.objectstorage.us-sanjose-1.oraclecloud.com"
)

# --- Logging setup -------------------------------------------------
# All script output (stdout and stderr) will be appended to $LOG_FILE.
exec >> "$LOG_FILE" 2>&1

# --- Functions -----------------------------------------------------
# Logs a message with a timestamp.
log() {
  echo "$(date +"%Y-%m-%d %H:%M:%S") - $*"
}

# --- Main ----------------------------------------------------------
# Check if the credentials file exists
if [ ! -f "$CREDENTIALS_FILE" ]; then
  log "ERROR: Credentials file '$CREDENTIALS_FILE' not found. Backup cannot proceed."
  exit 1
fi

log "INFO: Starting vmbackup..."

# Execute the vmbackup command
if sudo "${VM_BACKUP_CMD[@]}"; then
  log "INFO: vmbackup completed successfully."
else
  log "ERROR: vmbackup encountered an error. Please check the log for details."
  exit 1
fi

exit 0