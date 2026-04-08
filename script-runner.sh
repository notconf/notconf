#!/bin/bash
set -e

SCRIPT_DIR="yang-modules/scripts"
LOG_DIR="/log"
launched=0

if [ -d "$SCRIPT_DIR" ]; then
    for script in "$SCRIPT_DIR"/*; do
        [ -x "$script" ] || continue

        script_name=$(basename "$script")
        echo "Launching $script_name in background..."

        # Process substitution ensures $! captures the script's PID, not tee's
        "$script" > >(tee "$LOG_DIR/${script_name}.log") 2>&1 &
        script_pid=$!
        sleep 1
        if ! kill -0 "$script_pid" 2>/dev/null; then
            echo "Error: $script_name exited immediately."
            exit 1
        fi
        launched=1
    done
fi

if [ "$launched" -eq 1 ]; then
    echo "All scripts have been launched in the background."
fi
