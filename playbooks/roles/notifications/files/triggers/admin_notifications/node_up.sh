#!/bin/bash
MESSAGE=":large_green_circle: <!channel> $* has Resumed Operation"
sh /etc/slurm/triggers/trigger.sh $MESSAGE
