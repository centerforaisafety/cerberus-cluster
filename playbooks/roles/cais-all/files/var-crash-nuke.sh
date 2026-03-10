     #!/usr/bin/env bash
     set -euo pipefail

     if [[ $EUID -ne 0 ]]; then
         exec sudo "$0" "$@"
     fi

     if [ -d /var/crash ]; then
         rm -rf /var/crash/*
     fi

