#!/bin/bash
MESSAGE=":red_circle: <!channel> $* has Gone Down"
sh /etc/slurm/triggers/trigger.sh $MESSAGE
