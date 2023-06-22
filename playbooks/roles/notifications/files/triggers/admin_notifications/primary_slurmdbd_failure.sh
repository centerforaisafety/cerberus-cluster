#!/bin/bash
MESSAGE=":red_circle: <!channel> The Primary Database Controller Daemon has Failed"
sh /etc/slurm/triggers/trigger.sh $MESSAGE
