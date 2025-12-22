#!/bin/bash
SCRIPT_DIR="yang-modules/scripts"
LOG_DIR="/var/log/python_scripts"

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

if [ -d "$SCRIPT_DIR" ]; then
    for script in "$SCRIPT_DIR"/*.py; do
        [ -e "$script" ] || continue
        
        script_name=$(basename "$script")
        echo "Launching $script_name in background..."

        # Run in background (&), redirecting both stdout and stderr to a log file
        python3 "$script" > "$LOG_DIR/${script_name}.log" 2>&1 &
        
        # Immediate check if the process failed to start (e.g., syntax error)
        if [ $? -ne 0 ]; then
            echo "Error: Failed to launch $script_name."
        fi
    done
else
    echo "Directory $SCRIPT_DIR not found."
fi

# Final message before the runner script exits
echo "All scripts have been launched in the background. Container will remain active if started with -it."
