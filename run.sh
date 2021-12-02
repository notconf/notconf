#!/bin/bash

/load-yang-modules.sh
exec netopeer2-server -d -v3
