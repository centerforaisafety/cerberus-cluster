#!/bin/bash
MESSAGE=":large_yellow_circle: <!channel> The backup Slurm Controller Daemon has Resumed Operation"
sh /etc/slurm/triggers/trigger.sh $MESSAGE
