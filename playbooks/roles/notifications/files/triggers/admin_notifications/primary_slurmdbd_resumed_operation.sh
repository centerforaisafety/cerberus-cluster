#!/bin/bash
MESSAGE=":large_green_circle: <!channel> The Primary Database Daemon has Resumed Operation"
sh /etc/slurm/triggers/trigger.sh $MESSAGE
