# Fixup Makefile for IETF standard device models
# This builds a container image with core IETF device management models,
# primarily ietf-system for basic device management

# Get all YANG files from the RFC directory
YANGS=$(wildcard $(YANG_PATH)/*.yang)

# Include only these specific modules and their dependencies
INCLUDE_PATTERNS = \
	$(YANG_PATH)/iana-crypt-hash.yang \
	$(YANG_PATH)/ietf-inet-types.yang \
	$(YANG_PATH)/ietf-netconf-acm.yang \
	$(YANG_PATH)/ietf-system.yang \
	$(YANG_PATH)/ietf-yang-types.yang

# Exclude modules with date suffixes (keep only latest versions)
EXCLUDE += $(YANG_PATH)/%@*.yang

# Select only the modules we want
SELECTED_YANGS = $(filter $(INCLUDE_PATTERNS), $(filter-out $(EXCLUDE), $(YANGS)))

all: $(patsubst $(YANG_PATH)/%.yang,$(COMPOSE_PATH)/%.yang,$(SELECTED_YANGS))

$(COMPOSE_PATH)/%.yang: $(YANG_PATH)/%.yang
	@echo "Including IETF module: $<"
	cp $< $@
