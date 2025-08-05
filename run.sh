#!/bin/bash

/install-yang-modules.sh
/load-startup-config.sh
/watch.sh /yang-modules/operational python3 /load-oper-data.py --path /yang-modules/operational --sync-file /tmp/sync &
mkdir -p /log

# Start rousette RESTCONF server
rousette 2>&1 | tee /log/rousette.log &

# Start HTTP/2 proxy for RESTCONF
nghttpx --daemon --accesslog-file=/log/nghttpx.log --add-forwarded=for -f '*,80;no-tls' \
    -b '127.0.0.1,10080;/restconf/:/yang/:/streams/:/.well-known/;proto=h2'

# Start netopeer2-server in foreground
exec netopeer2-server -U -d -v2 2>&1 | tee /log/netopeer.log
