#!/bin/bash

if [ -d ${YANG_MODULES_DIR}/install ]; then MODULES=$(ls ${YANG_MODULES_DIR}/install | sed -e "s#^#${YANG_MODULES_DIR}/#");
else MODULES=$(ls ${YANG_MODULES_DIR}/*.yang); fi
for f in ${MODULES}; do
	if head -n1 $f | grep ^submodule > /dev/null 2>&1; then echo "Skipping submodule $f"; continue; fi
	echo "Loading module $f"
	time sysrepoctl --search-dirs ${YANG_MODULES_DIR} --install $f -v3
done
