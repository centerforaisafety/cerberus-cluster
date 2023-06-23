#!/bin/bash
MESSAGE=":large_green_circle: <!channel> The Primary Slurm Controller Daemon has Resumed Control"
sh /etc/slurm/triggers/trigger.sh $MESSAGE
