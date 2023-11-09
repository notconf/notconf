# Nokia YANG modules consist of the two main modules: nokia-conf.yang and
# nokia-state.yang and other smaller auxilliary modules. They have always
# provided the main models as a set of submodules that are then included in the
# top-level modules. In addition there is a 'nokia-combined' directory that
# contains pre-processed modules where no submodules are used.
# In the recent versions (22+) the release has changed, the top-level directory
# no longer includes the two main modules. Instead there are now two directories
# 'nokia-combined' and 'nokia-submodule' and the user must choose one. This
# fixup file should work for both cases - it will always attempt to use the
# files from 'nokia-submodule'.

YANGS=$(wildcard $(YANG_PATH)/*.yang)
YANGS_SUBMODULE=$(wildcard $(YANG_PATH)/nokia-submodule/*.yang)

all: $(YANGS:$(YANG_PATH)/%.yang=$(COMPOSE_PATH)/%.yang)
all: $(YANGS_SUBMODULE:$(YANG_PATH)/nokia-submodule/%.yang=$(COMPOSE_PATH)/%.yang)

vpath %.yang $(YANG_PATH)/nokia-submodule
vpath %.yang $(YANG_PATH)

$(COMPOSE_PATH)/%.yang: %.yang
	cp $< $@

.PHONY: all test test-sysrepo test-netopeer

test:
	$(CONTAINER_RUNTIME) cp operational $(CNT_PREFIX):/yang-modules
	$(CONTAINER_RUNTIME) exec $(CNT_PREFIX) /wait-operational-sync.sh
	$(MAKE) -C ../../../../perftest build-container-image
	$(MAKE) test-sysrepo
	$(MAKE) test-netopeer-xpath
	$(MAKE) test-netopeer-subtree

test-sysrepo:
	$(CONTAINER_RUNTIME) cp ../../../../perftest/test-sysrepo.py $(CNT_PREFIX):/
	$(CONTAINER_RUNTIME) exec $(CNT_PREFIX) /test-sysrepo.py --path "/state/chassis[chassis-class='router'][chassis-number='1']/peq[peq-slot='12']/equipped-type" -n 100

test-netopeer-xpath:
	$(CONTAINER_RUNTIME) run -t --rm --network container:$(CNT_PREFIX) --name $(CNT_PREFIX)-test-netconf test-netconf -n 100 -get-data -datastore operational -filter-xpath "/state/chassis[chassis-class='router'][chassis-number='1']/peq[peq-slot='12']/equipped-type"

test-netopeer-subtree:
	$(CONTAINER_RUNTIME) run -t --rm --network container:$(CNT_PREFIX) --name $(CNT_PREFIX)-test-netconf test-netconf -n 100 -get-data -datastore operational -filter-subtree "<state><chassis><chassis-class>router</chassis-class><chassis-number>1</chassis-number><peq><peq-slot>12</peq-slot><equipped-type/></peq></chassis></state>"
