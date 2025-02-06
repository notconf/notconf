# The quality of Cisco IOS XR YANG modules varies between releases. It seems
# that each release contains some broken modules. This fixup file works for
# building the 771 and 772 releases. It may work for other releases as well.

YANGS=$(wildcard $(YANG_PATH)/*.yang)

# When condition cyclic dependency on the node "best-effort"
EXCLUDE+=%Cisco-IOS-XR-cfgmgr-rollback-act.yang
# When condition cyclic dependency on the node "event-mode-match-first"
EXCLUDE+=%Cisco-IOS-XR-infra-policymgr-cfg.yang
ifneq (,$(findstring /771,$(YANG_PATH)))
# File size is 0
EXCLUDE+=$(YANG_PATH)/Cisco-IOS-XR-sysadmin-eobc-iosxrwbd.yang
# References the module above
EXCLUDE+=$(YANG_PATH)/Cisco-IOS-XR-sysadmin-controllers-iosxrwbd.yang
endif

# Generic fixups that apply to any version
# OpenConfig is broken
EXCLUDE+=$(YANG_PATH)/cisco-xr-openconfig-%
EXCLUDE+=$(YANG_PATH)/openconfig-%
EXCLUDE+=$(YANG_PATH)/Cisco-IOS-XR-openconfig-%
EXCLUDE+=$(YANG_PATH)/cisco-xr-ietf-%-deviations.yang
# Skip IETF modules
EXCLUDE+=$(YANG_PATH)/ietf-netconf.yang
EXCLUDE+=$(YANG_PATH)/iana-crypt-hash.yang

all: $(patsubst $(YANG_PATH)/%.yang,$(COMPOSE_PATH)/%.yang,$(filter-out $(EXCLUDE),$(YANGS)))

$(COMPOSE_PATH)/%.yang: $(YANG_PATH)/%.yang
# Copy file if it is not empty?!
	@if [ -s $< ]; then cp $< $@; fi

# 76x releases: When statements referencing nodes where they are defined
$(COMPOSE_PATH)/Cisco-IOS-XR-sysadmin-ethsw-esdma-sfp.yang: $(YANG_PATH)/Cisco-IOS-XR-sysadmin-ethsw-esdma-sfp.yang
	sed -e '/when "..\/q\?sfp-laser-wavelength/d' -e '/when "..\/qsfp-link-length/d' -e '/when "..\/sfp-link-reach/d' $< > $@
