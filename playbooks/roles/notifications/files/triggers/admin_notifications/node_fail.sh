#!/bin/bash
MESSAGE=":red_circle: <!channel> $* has Failed"
sh /etc/slurm/triggers/trigger.sh $MESSAGE
