#!/bin/bash
MESSAGE=":red_circle: <!channel> The backup Slurm Controller Daemon has Failed"
sh /etc/slurm/triggers/trigger.sh $MESSAGE
