#!/bin/bash

for f in `ls ${YANG_MODULES_DIR}/*.xml`; do
	echo "Loading startup config $f"
	sysrepocfg --edit=$f --datastore startup -v3
done

echo "Copying startup datastore to running"
sysrepocfg --datastore running --copy-from startup -v3
