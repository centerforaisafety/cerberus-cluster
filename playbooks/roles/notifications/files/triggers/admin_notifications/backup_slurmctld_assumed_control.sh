#!/bin/bash
MESSAGE=":large_yellow_circle: <!channel> The Backup Slurm Controller Daemon has Assumed Control"
sh /etc/slurm/triggers/trigger.sh $MESSAGE
