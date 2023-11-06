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

# This is the first stage of preparing the nokia modules where we strip the
# "incorrect" extension usage statement and collect all processed YANG modules
# to a single directory. The next stage then has access to everything.
$(COMPOSE_PATH)/strip/%.yang: %.yang
	@mkdir -p $(COMPOSE_PATH)/strip
# The extension instance appears in the 'meta-stms' header section in the YANG
# module - just before the 'organization' statement. libyang thinks that is not
# allowed, but looking at the YANG ABNF grammar we're not so sure. Extension
# statement instances are parsed as 'unknown-statement' which can appear
# anywhere! Let's strip the statement until libyang is fixed.
	sed -e '/sros-ext:sros-major-release/d' $< > $@

$(COMPOSE_PATH)/%.yang: $(COMPOSE_PATH)/strip/%.yang
	cp $< $@
	@mkdir -p $(COMPOSE_PATH)/install
# Mark the module for installation if it contains at least one data node. This
# saves time by skipping installation of nodes that only contain groupings or
# typedefs. Store pyang output in a temporary variable to ensure the YANG module
# gets marked for installation in case pyang (or xmlstarlet) fails to process
# the file.
	@if ! head -n1 $@ | grep -e '^submodule'; then \
		top_level_statements=$$(pyang --ignore-errors -f yin $@ -p $(COMPOSE_PATH)/strip | xmlstarlet sel -t -m '_:module/*' -v 'name()' -n); \
		if [ $$? -eq 0 ]; then echo $${top_level_statements} | grep -F -e container -e leaf -e leaf-list -e list -e choice -e anydata -e anyxml -e uses -e rpc -e action -e notification -e augment -e identity && touch $(COMPOSE_PATH)/install/$(@F); \
		else \
			touch $(COMPOSE_PATH)/install/$(@F); \
		fi \
	fi || true

.PHONY: all test test-sysrepo test-netopeer

test:
	$(CONTAINER_RUNTIME) cp operational $(CNT_PREFIX):/yang-modules
	$(CONTAINER_RUNTIME) exec $(CNT_PREFIX) /wait-operational-sync.sh
	$(MAKE) test-sysrepo
	$(MAKE) test-netopeer

test-sysrepo:
	$(CONTAINER_RUNTIME) cp test-sysrepo.py $(CNT_PREFIX):/
	$(CONTAINER_RUNTIME) exec $(CNT_PREFIX) /test-sysrepo.py --sysrepo --path "/state/chassis[chassis-class='router'][chassis-number='1']/peq[peq-slot='12']/equipped-type" -n 500

test-netopeer:
	-$(CONTAINER_RUNTIME) rm -f $(CNT_PREFIX)-ncclient
	$(CONTAINER_RUNTIME) create --rm --name $(CNT_PREFIX)-ncclient --network container:$(CNT_PREFIX) $(IMAGE_PATH)notconf:$(IMAGE_TAG)-debug /test-sysrepo.py --netopeer --path "/state/chassis[chassis-class='router'][chassis-number='1']/peq[peq-slot='12']/equipped-type" -n 500
	$(CONTAINER_RUNTIME) cp test-sysrepo.py $(CNT_PREFIX)-ncclient:/
	$(CONTAINER_RUNTIME) start -ai $(CNT_PREFIX)-ncclient
