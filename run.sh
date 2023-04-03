#!/bin/bash

/install-yang-modules.sh
/load-startup-config.sh
/watch.sh /yang-modules/operational python3 /load-oper-data.py --path /yang-modules/operational --sync-file /tmp/sync &
mkdir -p /log
exec netopeer2-server -U -d -v2 2>&1 | tee /log/netopeer.log
