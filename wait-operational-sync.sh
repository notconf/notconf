#!/bin/sh
echo "Triggering operational data sync"
touch /yang-modules/operational && inotifywait -e create -e modify --include 'sync$' /tmp >/dev/null 2>&1
echo "Operational data sync done!"
