all:

.PHONY: test test-sysrepo test-netopeer

test:
	$(MAKE) test-sysrepo
	$(MAKE) test-netopeer-xpath
	$(MAKE) test-netopeer-subtree

test-sysrepo:
	$(CONTAINER_RUNTIME) cp ../../../perftest/test-sysrepo.py $(CNT_PREFIX):/
	$(CONTAINER_RUNTIME) exec $(CNT_PREFIX) /test-sysrepo.py --path /bob/state/great

test-netopeer-xpath:
	$(CONTAINER_RUNTIME) cp ../../../perftest/test-netconf $(CNT_PREFIX):/
	$(CONTAINER_RUNTIME) exec $(CNT_PREFIX) /test-netconf -n 100 -get-data -datastore operational -filter-xpath /bob/state/great

test-netopeer-subtree:
	$(CONTAINER_RUNTIME) cp ../../../perftest/test-netconf $(CNT_PREFIX):/
	$(CONTAINER_RUNTIME) exec $(CNT_PREFIX) /test-netconf -n 100 -get-data -datastore operational -filter-subtree "<bob><state><great/></state></bob>"