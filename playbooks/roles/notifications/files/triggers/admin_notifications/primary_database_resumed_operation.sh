#!/bin/bash
MESSAGE=":large_green_circle: <!channel> The Primary Database has Resumed Operations"
sh /etc/slurm/triggers/trigger.sh $MESSAGE
