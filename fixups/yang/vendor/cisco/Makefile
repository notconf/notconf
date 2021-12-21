YANGS=$(wildcard $(YANG_PATH)/*.yang)
EXCLUDE=%CISCO-ENTITY-FRU-CONTROL-MIB.yang
# When condition cyclic dependency on the node "best-effort"
EXCLUDE+=%Cisco-IOS-XR-cfgmgr-rollback-act.yang
# When condition cyclic dependency on the node "event-mode-match-first"
EXCLUDE+=%Cisco-IOS-XR-infra-policymgr-cfg.yang

all: $(patsubst $(YANG_PATH)/%.yang,$(COMPOSE_PATH)/%.yang,$(filter-out $(EXCLUDE),$(YANGS)))

$(COMPOSE_PATH)/%.yang: $(YANG_PATH)/%.yang
	cp $< $@
