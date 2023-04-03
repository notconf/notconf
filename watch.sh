#!/bin/bash
#
# Simple directory watcher that restarts a script on any change in the monitored
# path.
#
# ./watch.sh </path/to/watch> <command argument1 argument2 ...>
#
# If the watcher is run in foreground you can interrupt it with Ctrl+c,
# otherwise send a SIGTERM to clean up the processes.

signal_handler()
{
    kill $PID
    exit
}

trap signal_handler SIGINT
trap signal_handler SIGTERM

while true; do
    if [ ! -d "$1" ]; then
        echo "Directory $1 does not exist, waiting for it to appear";
        inotifywait -e create --include $(basename $1)\$ $(dirname $1)
    else
        ${@:2} &
        PID=$!
        inotifywait -e modify -e move -e create -e delete -e attrib -r $1
        kill $PID
    fi
done
