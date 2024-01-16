all:

.PHONY: test test-sysrepo test-netopeer

test:
	$(MAKE) -C ../../../perftest build-container-image
	$(MAKE) test-sysrepo
	$(MAKE) test-netopeer-xpath
	$(MAKE) test-netopeer-subtree

test-sysrepo:
	$(CONTAINER_RUNTIME) cp ../../../perftest/test-sysrepo.py $(CNT_PREFIX):/
	$(CONTAINER_RUNTIME) exec $(CNT_PREFIX) /test-sysrepo.py --path /test:bob/state/great

test-netopeer-xpath:
	$(CONTAINER_RUNTIME) run -t --rm --network container:$(CNT_PREFIX) --name $(CNT_PREFIX)-test-netconf test-netconf -n 100 -get-data -datastore operational -namespace test=\'urn:notconf:test\' -filter-xpath /test:bob/state/great

test-netopeer-subtree:
	$(CONTAINER_RUNTIME) run -t --rm --network container:$(CNT_PREFIX) --name $(CNT_PREFIX)-test-netconf test-netconf -n 100 -get-data -datastore operational -filter-subtree "<bob xmlns='urn:notconf:test'><state><great/></state></bob>"
