#!/bin/bash

if [ -d ${YANG_MODULES_DIR}/install ]; then MODULES=$(ls ${YANG_MODULES_DIR}/install | sed -e "s#^#${YANG_MODULES_DIR}/#");
else MODULES=$(ls ${YANG_MODULES_DIR}/*.yang); fi

n=0
total=$(echo "${MODULES}" | wc -l)
declare -a install_modules=()

# Stop installing modules on errors
set -e

# Skip submodules as they will automatically be installed with their parent
for f in ${MODULES}; do
	n=$((n+1))
	if head -n1 $f | grep ^submodule > /dev/null 2>&1; then echo "[$n/$total] Skipping submodule $f"; continue; fi
	echo "[$n/$total] Preparing to install module $f"
	install_modules+=($f)
done

if [ ${#install_modules[@]} -eq 0 ]; then
	echo "No modules to install"
	exit 0
fi

# Add --install flag to each module name
install_modules=( "${install_modules[@]/#/--install }" )

# Install all modules in a single batch (recent-ish feature
# https://github.com/CESNET/netopeer2/issues/1337#issuecomment-1403225980)
time sysrepoctl --search-dirs ${YANG_MODULES_DIR} ${install_modules[@]} -v3
