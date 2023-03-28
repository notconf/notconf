#!/bin/bash

/install-yang-modules.sh
/load-startup-config.sh
/watch.sh /yang-modules/operational python3 /load-oper-data.py --path /yang-modules/operational &
mkdir -p /log
exec netopeer2-server -d -v2 2>&1 | tee /log/netopeer.log
