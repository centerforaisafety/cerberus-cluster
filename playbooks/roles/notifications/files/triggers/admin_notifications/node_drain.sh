#!/bin/bash
MESSAGE=":red_circle: <!channel> $* has Drained"
sh /etc/slurm/triggers/trigger.sh $MESSAGE
