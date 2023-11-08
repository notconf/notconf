all:

.PHONY: test test-sysrepo test-netopeer

test:
	$(MAKE) -C ../../../perftest build-container-image
	$(MAKE) test-sysrepo
	$(MAKE) test-netopeer-xpath
	$(MAKE) test-netopeer-subtree

test-sysrepo:
	$(CONTAINER_RUNTIME) cp ../../../perftest/test-sysrepo.py $(CNT_PREFIX):/
	$(CONTAINER_RUNTIME) exec $(CNT_PREFIX) /test-sysrepo.py --path /bob/state/great

test-netopeer-xpath:
	$(CONTAINER_RUNTIME) run -t --rm --network container:$(CNT_PREFIX) --name $(CNT_PREFIX)-test-netconf test-netconf -n 100 -get-data -datastore operational -filter-xpath /bob/state/great

test-netopeer-subtree:
	$(CONTAINER_RUNTIME) run -t --rm --network container:$(CNT_PREFIX) --name $(CNT_PREFIX)-test-netconf test-netconf -n 100 -get-data -datastore operational -filter-subtree "<bob><state><great/></state></bob>"
