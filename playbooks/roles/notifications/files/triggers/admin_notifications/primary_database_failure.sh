#!/bin/bash
MESSAGE=":red_circle: <!channel> The Primary database has Failed"
sh /etc/slurm/triggers/trigger.sh $MESSAGE
