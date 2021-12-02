#!/bin/bash

for f in `ls ${YANG_MODULES_DIR}/*.yang`; do
	if head -n1 $f | grep ^submodule > /dev/null 2>&1; then echo "Skipping submodule $f"; continue; fi
	echo "Loading module $f"
	time sysrepoctl --search-dirs ${YANG_MODULES_DIR} --install $f -v3
done
