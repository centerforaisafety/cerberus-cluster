#!/bin/bash
MESSAGE=":red_circle: <!channel> The Primary Slurm Controller Daemon Accounting Buffer is Full"
sh /etc/slurm/triggers/trigger.sh $MESSAGE
