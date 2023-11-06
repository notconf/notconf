all:

.PHONY: test test-sysrepo test-netopeer

test:
	$(MAKE) test-sysrepo
	$(MAKE) test-netopeer

test-sysrepo:
	$(CONTAINER_RUNTIME) cp test-sysrepo.py $(CNT_PREFIX):/
	$(CONTAINER_RUNTIME) exec $(CNT_PREFIX) /test-sysrepo.py --sysrepo --path /bob/state/great

test-netopeer:
