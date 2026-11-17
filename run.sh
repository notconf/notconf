#!/bin/bash

set -e

# sysrepo SHM files are on disk and would survive a container restart
[ -z "$SYSREPO_SHM_DIR" ] || rm -f "$SYSREPO_SHM_DIR"/sr*

/install-yang-modules.sh
/load-startup-config.sh
/watch.sh /yang-modules/operational python3 /load-oper-data.py --path /yang-modules/operational --sync-file /tmp/sync &
mkdir -p /log
/script-runner.sh

# Start rousette RESTCONF server
rousette 2>&1 | tee /log/rousette.log &

# Start HTTP/2 proxy for RESTCONF
nghttpx --daemon --accesslog-file=/log/nghttpx.log --add-forwarded=for -f '*,80;no-tls' \
    -b '127.0.0.1,10080;/restconf/:/yang/:/streams/:/.well-known/;proto=h2'

# Start netopeer2-server in foreground
exec netopeer2-server -U unix-socket:/var/run/netopeer2-server.sock -d -v2 2>&1 | tee /log/netopeer.log
