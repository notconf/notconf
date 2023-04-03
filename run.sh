#!/bin/bash

/install-yang-modules.sh
/load-startup-config.sh
mkdir -p /log
exec netopeer2-server -U -d -v2 2>&1 | tee /log/netopeer.log
