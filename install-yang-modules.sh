#!/bin/bash

if [ -d ${YANG_MODULES_DIR}/install ]; then MODULES=$(ls ${YANG_MODULES_DIR}/install | sed -e "s#^#${YANG_MODULES_DIR}/#");
else MODULES=$(ls ${YANG_MODULES_DIR}/*.yang); fi

n=0
total=$(echo "${MODULES}" | wc -l)
# Stop installing modules on errors
set -e
for f in ${MODULES}; do
	n=$((n+1))
	if head -n1 $f | grep ^submodule > /dev/null 2>&1; then echo "[$n/$total] Skipping submodule $f"; continue; fi
	echo "[$n/$total] Installing module $f"
	time sysrepoctl --search-dirs ${YANG_MODULES_DIR} --install $f -v3
done
