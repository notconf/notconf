#!/bin/bash

/install-yang-modules.sh
/load-initial-config.sh
exec netopeer2-server -d -v3
