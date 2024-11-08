# Defines the container runtime to use for building images and running tests. We
# default to "docker" because it works in most environments. Most users will
# have Docker installed, or use Podman with the "alias docker=podman" set up. In
# GitHub actions runner VM (ubuntu) both Podman and Docker are installed so we
# set this variable to "podman" because we want to use it in CI.
export CONTAINER_RUNTIME?=docker

# helper function to turn a string into lower case
lc = $(subst A,a,$(subst B,b,$(subst C,c,$(subst D,d,$(subst E,e,$(subst F,f,$(subst G,g,$(subst H,h,$(subst I,i,$(subst J,j,$(subst K,k,$(subst L,l,$(subst M,m,$(subst N,n,$(subst O,o,$(subst P,p,$(subst Q,q,$(subst R,r,$(subst S,s,$(subst T,t,$(subst U,u,$(subst V,v,$(subst W,w,$(subst X,x,$(subst Y,y,$(subst Z,z,$1))))))))))))))))))))))))))
ifneq ($(CI_REGISTRY),)
export IMAGE_PATH?=$(call lc,$(CI_REGISTRY)/$(CI_PROJECT_NAMESPACE)/notconf/)
endif

ifneq ($(CI_PIPELINE_ID),)
PNS:=$(CI_PIPELINE_ID)
else ifneq ($(GITHUB_RUN_ID),)
PNS:=$(GITHUB_RUN_ID)
else
PNS:=$(shell whoami | sed 's/[^[:alnum:]._-]\+/_/g')
endif

# If we are running in CI and on the default branch (like 'main' or 'master'),
# disable the build cache for docker builds. We do this with ?= operator in
# make so we only set DOCKER_BUILD_CACHE_ARG if it is not already set, this
# makes it possible to still use the cache if explicitly set through
# environment variables in CI.
ifneq ($(CI),)
ifeq ($(CI_COMMIT_REF_NAME),$(CI_DEFAULT_BRANCH))
DOCKER_BUILD_CACHE_ARG?=--no-cache
endif
endif

export IMAGE_TAG?=$(PNS)

# BuildKit speeds up the image builds by running independent stages in a
# multi-stage Dockerfile concurrently. BuildKit is a breeze to use with Docker -
# everything just works automagically when you set the env var. The process is a
# bit more involved when using Podman so we are currently only using BuildKit on
# Docker.
export DOCKER_BUILDKIT=1
# The standardized OCI image spec does not store the healthcheck in image
# metadata, so there is no support for the HEALTHCHECK directive in the
# Dockerfile. We can use the "docker" image spec with Podman.
export BUILDAH_FORMAT=docker

.PHONY: clone-deps build test tag-release push-release push test tag-release-composed-notconf push-release-composed-notconf

clone-or-update: BRANCH?=devel
clone-or-update: DIR:=$(basename $(lastword $(subst /, ,$(REPOSITORY))))
clone-or-update:
	@mkdir -p src
	if ! git clone $(REPOSITORY) src/$(DIR); then \
		cd src/$(DIR); \
		git fetch origin; \
	fi
	cd src/$(DIR); \
	git checkout $(BRANCH); \
# Reset to origin branch if it exists, otherwise reset to commit hash \
	git show-ref --verify refs/remotes/origin/$(BRANCH) 2>&1 >/dev/null && git reset --hard origin/$(BRANCH) || git reset --hard $(BRANCH); \

# The sysrepo / netopeer2 projects appear to use a git workflow where the
# 'master' branch is stable and the 'devel' branch is the integration branch
# where new features and fixes first get introduced or merged. The pace of
# changes in the development branch is quite high which makes it difficult to
# keep up with new features (and bugs) so we now have the option of pinning a
# specific version (hash) of the development branches.
# These are defined in the versions.json file. The top dictionary key is the
# branch name or our custom pinning name. The value is a dictionary with the
# keys being the project names and the values being the git commit hash or
# branch name. If the branch name is not defined for a project, the default is
# to use the branch name from the top level dictionary.
PIN_NAME?=2024-01-16
clone-deps:
	$(MAKE) clone-or-update REPOSITORY=https://github.com/CESNET/libyang.git BRANCH=$(shell jq --raw-output '."$(PIN_NAME)"."libyang" // "$(PIN_NAME)"' versions.json)
	$(MAKE) clone-or-update REPOSITORY=https://github.com/sysrepo/sysrepo.git BRANCH=$(shell jq --raw-output '."$(PIN_NAME)"."sysrepo" // "$(PIN_NAME)"' versions.json)
	$(MAKE) clone-or-update REPOSITORY=http://git.libssh.org/projects/libssh.git BRANCH=$(shell jq --raw-output '."$(PIN_NAME)"."libssh" // "$(PIN_NAME)"' versions.json)
	$(MAKE) clone-or-update REPOSITORY=https://github.com/CESNET/libnetconf2.git BRANCH=$(shell jq --raw-output '."$(PIN_NAME)"."libnetconf2" // "$(PIN_NAME)"' versions.json)
	$(MAKE) clone-or-update REPOSITORY=https://github.com/CESNET/netopeer2.git BRANCH=$(shell jq --raw-output '."$(PIN_NAME)"."netopeer2" // "$(PIN_NAME)"' versions.json)

CONTAINER_BUILD_ARGS=--build-arg SYSREPO_PYTHON_VERSION=$(shell jq --raw-output '."$(PIN_NAME)"."sysrepo-python" // "$(PIN_NAME)"' versions.json) --build-arg LIBYANG_PYTHON_VERSION=$(shell jq --raw-output '."$(PIN_NAME)"."libyang-python" // "$(PIN_NAME)"' versions.json)
build:
# We explicitly build the first 'build-tools-source' stage (where the
# dependencies are installed and source code is pulled), which allows us to
# control caching of it through the DOCKER_BUILD_CACHE_ARG.
	$(CONTAINER_RUNTIME) build --target build-tools-source $(DOCKER_BUILD_CACHE_ARG) .
	$(CONTAINER_RUNTIME) build --target notconf-release -t $(IMAGE_PATH)notconf:$(IMAGE_TAG) --build-arg BUILD_TYPE=Release $(CONTAINER_BUILD_ARGS) .
	$(CONTAINER_RUNTIME) build --target notconf-debug -t $(IMAGE_PATH)notconf:$(IMAGE_TAG)-debug --build-arg BUILD_TYPE=Debug $(CONTAINER_BUILD_ARGS) .

tag-release:
	$(CONTAINER_RUNTIME) tag $(IMAGE_PATH)notconf:$(IMAGE_TAG) $(IMAGE_PATH)notconf:latest
	$(CONTAINER_RUNTIME) tag $(IMAGE_PATH)notconf:$(IMAGE_TAG)-debug $(IMAGE_PATH)notconf:debug

push-release:
	$(CONTAINER_RUNTIME) push $(IMAGE_PATH)notconf:debug
	$(CONTAINER_RUNTIME) push $(IMAGE_PATH)notconf:latest

push:
	$(CONTAINER_RUNTIME) push $(IMAGE_PATH)notconf:$(IMAGE_TAG)
	$(CONTAINER_RUNTIME) push $(IMAGE_PATH)notconf:$(IMAGE_TAG)-debug

tag-release-composed-notconf: composed-notconf.txt
	for tag in $$(uniq $<); do release_tag=$$(echo $${tag} | sed 's/-$(PNS)$$//'); $(CONTAINER_RUNTIME) tag $${tag} $${release_tag}; done

push-release-composed-notconf: composed-notconf.txt
	for release_tag in $$(sed 's/-$(PNS)$$//g' $< | uniq); do $(CONTAINER_RUNTIME) push $${release_tag}; done

push-composed-notconf: composed-notconf.txt
	for tag in $$(uniq $<); do $(CONTAINER_RUNTIME) push $${tag}; done

test:
	$(MAKE) test-notconf-mount
	$(MAKE) test-compose-yang YANG_PATH=test/yang-modules

test-yangmodels:
	> composed-notconf.txt
	$(MAKE) test-compose-yang YANG_PATH=yang/vendor/nokia/7x50_YangModels/latest_sros_21.20
	$(MAKE) test-compose-yang YANG_PATH=yang/vendor/nokia/7x50_YangModels/latest_sros_22.2
	$(MAKE) test-compose-yang YANG_PATH=yang/vendor/juniper/21.1/21.1R1/junos
	#$(MAKE) test-compose-yang YANG_PATH=yang/vendor/cisco/xr/771

# test-notconf-mount: start a notconf:latest container with the test YANG
# modules mounted to /yang-modules in the container. All YANG modules and XML
# init files in the directory are installed into sysrepo automatically at
# container startup.
test-notconf-mount: export CNT_PREFIX=test-notconf-mount-$(PNS)
test-notconf-mount:
	-$(CONTAINER_RUNTIME) rm -f $(CNT_PREFIX)
# Usually we would start the notconf container with the desired YANG module
# (located on host) mounted to /yang-modules (in container). When the test
# itself is executed in a (CI runner) container bind mounting a path won't work
# because the path does not exist on the host, only in the test container. As a
# workaround we first create the container and then copy the YANG module to the
# target location. The following command would probably work on your local machine:
#	$(CONTAINER_RUNTIME) run -d --name $(CNT_PREFIX) -v $$(pwd)/test/yang-modules:/yang-modules $(IMAGE_PATH)notconf:$(IMAGE_TAG)
	$(CONTAINER_RUNTIME) create --log-driver json-file --name $(CNT_PREFIX) $(IMAGE_PATH)notconf:$(IMAGE_TAG)
	$(CONTAINER_RUNTIME) cp test/yang-modules $(CNT_PREFIX):/
	$(CONTAINER_RUNTIME) start $(CNT_PREFIX)
	$(MAKE) wait-healthy
	$(CONTAINER_RUNTIME) run -i --rm --network container:$(CNT_PREFIX) $(IMAGE_PATH)notconf:$(IMAGE_TAG)-debug netconf-console2 --port 830 --get-config -x /bob/startup | grep Robert
	$(CONTAINER_RUNTIME) run -i --rm --network container:$(CNT_PREFIX) $(IMAGE_PATH)notconf:$(IMAGE_TAG)-debug netconf-console2 --port 830 --ns test=urn:notconf:test --set /test:bob/test:bert=Robert
	$(CONTAINER_RUNTIME) run -i --rm --network container:$(CNT_PREFIX) $(IMAGE_PATH)notconf:$(IMAGE_TAG)-debug netconf-console2 --port 830 --get-config -x /bob/bert | grep Robert
	$(CONTAINER_RUNTIME) run -i --rm --network container:$(CNT_PREFIX) $(IMAGE_PATH)notconf:$(IMAGE_TAG)-debug netconf-console2 --port 830 --get -x /bob/state/great | grep success
	$(CONTAINER_RUNTIME) run -i --rm --network container:$(CNT_PREFIX) $(IMAGE_PATH)notconf:$(IMAGE_TAG)-debug netconf-console2 --port 830 --get-config -x /bob/alice | grep super
	$(MAKE) save-logs
	$(MAKE) test-stop

test-stop: CNT_PREFIX?=test-notconf
test-stop:
	$(CONTAINER_RUNTIME) ps -aqf name=$(CNT_PREFIX) | xargs --no-run-if-empty $(CONTAINER_RUNTIME) rm -f

# This test exports the images we built with Podman to Docker and then runs the
# test suite in Docker. Obviously both container runtimes must be installed on
# the machine.
test-podman-to-docker:
	podman save $(IMAGE_PATH)notconf:$(IMAGE_TAG) | docker load
	podman save $(IMAGE_PATH)notconf:$(IMAGE_TAG)-debug | docker load
	CONTAINER_RUNTIME=docker $(MAKE) test

save-logs: CNT_PREFIX?=test-notconf
save-logs:
	mkdir -p container-logs
	@for c in $$($(CONTAINER_RUNTIME) ps -af name=$(CNT_PREFIX) --format '{{.Names}}'); do \
		echo "== Collecting $(CONTAINER_RUNTIME) logs from $${c}"; \
		$(CONTAINER_RUNTIME) logs --timestamps $${c} > container-logs/$(CONTAINER_RUNTIME)_$${c}.log 2>&1; \
		$(CONTAINER_RUNTIME) inspect $${c} > container-logs/$(CONTAINER_RUNTIME)_$${c}_inspect.log; \
		$(CONTAINER_RUNTIME) run -i --rm --network container:$${c} $(IMAGE_PATH)notconf:$(IMAGE_TAG)-debug netconf-console2 --port 830 --hello > container-logs/$(CONTAINER_RUNTIME)_$${c}_netconf.log || true; \
	done

SHELL=/bin/bash

wait-healthy:
	@echo "Waiting (up to 900 seconds) for containers with prefix $(CNT_PREFIX) to become healthy"
ifeq ($(CONTAINER_RUNTIME),docker)
	@OLD_COUNT=0; for I in $$(seq 1 900); do \
		STOPPED=$$($(CONTAINER_RUNTIME) ps -a --filter name=$(CNT_PREFIX) | grep "Exited"); \
		if [ -n "$${STOPPED}" ]; then \
			echo -e "\e[31m===  $${SECONDS}s elapsed - Container(s) unexpectedly exited"; \
			echo -e "$${STOPPED} \\e[0m"; \
			exit 1; \
		fi; \
		COUNT=$$($(CONTAINER_RUNTIME) ps --filter name=$(CNT_PREFIX) | egrep "(unhealthy|health: starting)" | wc -l); \
		if [ $${COUNT} -gt 0 ]; then  \
			if [ $${OLD_COUNT} -ne $${COUNT} ];\
			then \
				echo -e "\e[31m===  $${SECONDS}s elapsed - Found unhealthy/starting ($${COUNT}) containers";\
				$(CONTAINER_RUNTIME) ps --filter name=$(CNT_PREFIX) | egrep "(unhealthy|health: starting)" | awk '{ print $$(NF) }';\
				echo -e "Checking again every 1 second, no more messages until changes detected\\e[0m"; \
			fi;\
			sleep 1; \
			OLD_COUNT=$${COUNT};\
			continue; \
		else \
			echo -e "\e[32m=== $${SECONDS}s elapsed - Did not find any unhealthy containers, all is good.\e[0m"; \
			exit 0; \
		fi ;\
	done; \
	echo -e "\e[31m===  $${SECONDS}s elapsed - Found unhealthy/starting ($${COUNT}) containers";\
	$(CONTAINER_RUNTIME) ps -a --filter name=$(CNT_PREFIX) --format 'table {{.Names}}\t{{.Status}}'; \
	echo -e "\e[0m"; \
	exit 1
else
# This is a compatibility hack for old podman (3.x) not properly reading the
# healtcheck config from (docker) image metadata. The containers start without a
# healthcheck so we have to emulate it here. This is supposedly fixed in 4.x:
# https://github.com/containers/podman/pull/12239
	@OLD_COUNT=0; for I in $$(seq 1 900); do \
		STOPPED=$$($(CONTAINER_RUNTIME) ps -a --filter name=$(CNT_PREFIX) | grep "Exited"); \
		if [ -n "$${STOPPED}" ]; then \
			echo -e "\e[31m===  $${SECONDS}s elapsed - Container(s) unexpectedly exited"; \
			echo -e "$${STOPPED} \\e[0m"; \
			exit 1; \
		fi; \
		CONTAINERS=$$($(CONTAINER_RUNTIME) ps -aq --filter name=$(CNT_PREFIX)); \
		TOTAL_COUNT=$$(echo "${CONTAINERS}" | wc -l); \
		HEALTHY_COUNT=$$($(CONTAINER_RUNTIME) logs $${CONTAINERS} | egrep 'Listening on .* for SSH connections' | wc -l); \
		COUNT=$$(echo "$${TOTAL_COUNT}-$${HEALTHY_COUNT}" | bc); \
		if [ $$COUNT -gt 0 ]; then  \
			if [ $$OLD_COUNT -ne $$COUNT ];\
			then \
				echo -e "\e[31m===  $${SECONDS}s elapsed - Found unhealthy/starting ($${COUNT}) containers";\
				$(CONTAINER_RUNTIME) ps -f name=$(CNT_PREFIX) | egrep "(unhealthy|health: starting)" | awk '{ print $$(NF) }';\
				echo -e "Checking again every 1 second, no more messages until changes detected\\e[0m"; \
			fi;\
			sleep 1; \
			OLD_COUNT=$$COUNT;\
			continue; \
		else \
			echo -e "\e[32m=== $${SECONDS}s elapsed - Did not find any unhealthy containers, all is good.\e[0m"; \
			exit 0; \
		fi ;\
	done; \
	echo -e "\e[31m===  $${SECONDS}s elapsed - Found unhealthy/starting ($${COUNT}) containers";\
	$(CONTAINER_RUNTIME) ps -a --filter name=$(CNT_PREFIX) --format 'table {{.Names}}\t{{.Status}}'; \
	echo -e "\e[0m"; \
	exit 1
endif

.PHONY: clone-yangmodels compose-notconf-yang test-compose-yang test-composed-notconf-yang

# clone-yangmodels: clones and checks out the yangmodels/yang repository
# including submodules
clone-yangmodels:
	if [ ! -d yang ]; then \
		git clone --depth 1 --recurse-submodules=vendor --shallow-submodules https://github.com/yangmodels/yang.git; \
	else \
		cd yang; \
		git pull && git submodule update --recursive --recommend-shallow; \
	fi

# Set up COMPOSE_IMAGE_* variables by examining the provided YANG_PATH variable.
# The conditions below knows how to extract the platform and version from the
# yangmodules/yang paths. If none match, default to just using YANG_PATH.
EXPLODED_YANG_PATH=$(subst /, ,$(YANG_PATH))
ifneq (,$(findstring latest_sros,$(YANG_PATH)))
	COMPOSE_IMAGE_NAME?=sros
	COMPOSE_IMAGE_TAG?=$(subst latest_sros_,,$(filter latest_sros%,$(EXPLODED_YANG_PATH)))
else ifneq (,$(findstring junos,$(YANG_PATH)))
# .../vendor/juniper/20.1/20.1R1/junos
# last word is the os - junos
	COMPOSE_IMAGE_NAME?=$(lastword $(EXPLODED_YANG_PATH))
# second to last word is the version - 21.1R1
	COMPOSE_IMAGE_TAG?=$(lastword $(filter-out $(lastword $(EXPLODED_YANG_PATH)),$(EXPLODED_YANG_PATH)))
else ifneq (,$(findstring cisco,$(YANG_PATH)))
# .../vendor/cisco/xr/751
# 3rd and 2nd words from the right are the os - cisco-xr
	COMPOSE_IMAGE_NAME?=cisco-$(lastword $(filter-out $(lastword $(EXPLODED_YANG_PATH)),$(EXPLODED_YANG_PATH)))
	COMPOSE_IMAGE_TAG?=$(lastword $(EXPLODED_YANG_PATH))
else
	COMPOSE_IMAGE_NAME?=$(subst /,_,$(patsubst %/,%,$(YANG_PATH)))
	COMPOSE_IMAGE_TAG?=latest
endif

# compose-notconf-yang: build a docker image with notconf:base with the given
# YANG modules already installed. Provide the path to the modules (and init
# XMLs) with the YANG_PATH variable.
compose-notconf-yang: COMPOSE_PATH=build/$(COMPOSE_IMAGE_NAME)/$(COMPOSE_IMAGE_TAG)
compose-notconf-yang:
	@if [ -z "$(YANG_PATH)" ]; then echo "The YANG_PATH variable must be set"; exit 1; fi
	rm -rf $(COMPOSE_PATH)
	mkdir -p $(COMPOSE_PATH)
	@set -e; \
	for fixup in `find fixups -type f -name Makefile -printf "%d %P\n" | sort -n -r | awk '{ print $$2; }'`; do \
		if [[ "$(YANG_PATH)" =~ ^$$(dirname $${fixup}).* ]]; then \
			echo "Executing fixups/$${fixup}"; \
			make -f fixups/$$fixup -j YANG_PATH=$(YANG_PATH) COMPOSE_PATH=$(COMPOSE_PATH); \
		fi \
	done
	if ! ls $(COMPOSE_PATH)/*.yang > /dev/null 2>&1; then \
		echo "Copying files directly from $(YANG_PATH) without fixups"; \
		cp -av $(YANG_PATH)/. $(COMPOSE_PATH); \
	fi
	$(CONTAINER_RUNTIME) build -f Dockerfile.yang -t $(IMAGE_PATH)notconf-$(COMPOSE_IMAGE_NAME):$(COMPOSE_IMAGE_TAG)-$(PNS) \
		--build-arg COMPOSE_PATH=$(COMPOSE_PATH) --build-arg IMAGE_PATH=$(IMAGE_PATH) --build-arg IMAGE_TAG=$(IMAGE_TAG) $(DOCKER_BUILD_CACHE_ARG) \
		--label org.opencontainers.image.description="This image contains the base notconf installation (sysrepo+netopeer2) with the following YANG modules pre-installed: $(COMPOSE_IMAGE_NAME)/$(COMPOSE_IMAGE_TAG)" .
	echo $(IMAGE_PATH)notconf-$(COMPOSE_IMAGE_NAME):$(COMPOSE_IMAGE_TAG)-$(PNS) >> composed-notconf.txt

test-compose-yang: compose-notconf-yang
	$(MAKE) test-composed-notconf-yang

test-composed-notconf-yang: export CNT_PREFIX=test-yang-$(COMPOSE_IMAGE_NAME)-$(COMPOSE_IMAGE_TAG)-$(PNS)
test-composed-notconf-yang:
	-$(CONTAINER_RUNTIME) rm -f $(CNT_PREFIX)
	$(CONTAINER_RUNTIME) run -d --log-driver json-file --name $(CNT_PREFIX) $(IMAGE_PATH)notconf-$(COMPOSE_IMAGE_NAME):$(COMPOSE_IMAGE_TAG)-$(PNS)
	$(MAKE) wait-healthy
	$(CONTAINER_RUNTIME) run -i --rm --network container:$(CNT_PREFIX) $(IMAGE_PATH)notconf:$(IMAGE_TAG)-debug netconf-console2 --port 830 --hello
	$(CONTAINER_RUNTIME) run -i --rm --network container:$(CNT_PREFIX) $(IMAGE_PATH)notconf:$(IMAGE_TAG)-debug netconf-console2 --port 830 --get -x /modules-state
	set -e; for fixup in `find fixups -type f -name Makefile -printf "%d %P\n" | sort -n -r | awk '{ print $$2; }'`; do \
		if [[ "$(YANG_PATH)" =~ ^$$(dirname $${fixup}).* ]] && make -C $$(dirname "fixups/$${fixup}") -n test >/dev/null 2>&1; then \
			echo "Executing test in fixups/$${fixup}"; \
			make -C $$(dirname "fixups/$${fixup}") test; \
		fi \
	done
	$(MAKE) save-logs
	$(MAKE) test-stop

# Print the value of a variable, for debugging / CI
print-%:
	@echo $*=$($*)
