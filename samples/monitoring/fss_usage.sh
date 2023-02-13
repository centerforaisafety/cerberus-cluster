#!/bin/bash

# TODO switch to duc #13
sudo du -sh /data/* | sort -rh > ~/logs/fss_du.log
