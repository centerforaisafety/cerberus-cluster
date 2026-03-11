#!/usr/bin/env bash
set -euo pipefail

# Nuke /var/crash
/usr/local/sbin/var-crash-nuke.sh

# Selective /tmp cleanup
/usr/local/sbin/tmp-cleaner.sh

