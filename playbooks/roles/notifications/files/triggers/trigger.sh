#!/bin/bash
WEBHOOK=$WEBHOOK_URL
timestamp=$(date +%F_%T.%3N_%Z)
curl -X POST -H 'Content-type: application/json' --data "{'text':'$* at $timestamp'}" $WEBHOOK