# Older versions of Juniper YANG modules are placed in the conf directory
all: $(patsubst $(YANG_PATH)/conf/%.yang,$(COMPOSE_PATH)/%.yang,$(wildcard $(YANG_PATH)/conf/*.yang))
all: $(patsubst $(YANG_PATH)/../common/%.yang,$(COMPOSE_PATH)/%.yang,$(wildcard $(YANG_PATH)/../common/*.yang))

# Newer versions of Juniper YANG modules are placed in the conf/models directory
all: $(patsubst $(YANG_PATH)/conf/models/%.yang,$(COMPOSE_PATH)/%.yang,$(wildcard $(YANG_PATH)/conf/models/*.yang))
all: $(patsubst $(YANG_PATH)/../common/models/%.yang,$(COMPOSE_PATH)/%.yang,$(wildcard $(YANG_PATH)/../common/models/*.yang))

vpath %.yang $(YANG_PATH)/conf
vpath %.yang $(YANG_PATH)/../common

vpath %.yang $(YANG_PATH)/conf/models
vpath %.yang $(YANG_PATH)/../common/models

$(COMPOSE_PATH)/%.yang: %.yang
# Use single quotes instead of double quotes for [pattern "\*"] statements
# (matching literal *). All the validators on
# https://yangvalidator.com/yangvalidator complain about double quotes so it
# must be something ...
	sed "s:\"\\\\\*\":'\\\\\*':g" $< > $@
