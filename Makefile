# Defines the container runtime to use for building images and running tests. We
# default to "docker" because it works in most environments. Most users will
# have Docker installed, or use Podman with the "alias docker=podman" set up. In
# GitHub actions runner VM (ubuntu) both Podman and Docker are installed so we
# set this variable to "podman" because we want to use it in CI.
CONTAINER_RUNTIME?=docker

# helper function to turn a string into lower case
lc = $(subst A,a,$(subst B,b,$(subst C,c,$(subst D,d,$(subst E,e,$(subst F,f,$(subst G,g,$(subst H,h,$(subst I,i,$(subst J,j,$(subst K,k,$(subst L,l,$(subst M,m,$(subst N,n,$(subst O,o,$(subst P,p,$(subst Q,q,$(subst R,r,$(subst S,s,$(subst T,t,$(subst U,u,$(subst V,v,$(subst W,w,$(subst X,x,$(subst Y,y,$(subst Z,z,$1))))))))))))))))))))))))))
ifneq ($(CI_REGISTRY),)
IMAGE_PATH?=$(call lc,$(CI_REGISTRY)/$(CI_PROJECT_NAMESPACE)/)
endif

ifneq ($(CI_PIPELINE_ID),)
PNS:=$(CI_PIPELINE_ID)
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

DOCKER_TAG?=$(PNS)

.PHONY: build test tag-release push-release push test

clone-or-update: BRANCH?=devel
clone-or-update: DIR:=$(basename $(lastword $(subst /, ,$(REPOSITORY))))
clone-or-update:
	@mkdir -p src
	if ! git clone -b $(BRANCH) $(REPOSITORY) src/$(DIR); then \
		cd src/$(DIR); \
		git fetch origin; \
		git checkout $(BRANCH); \
	fi

LIBYANG_TAG=v2.0.231
SYSREPO_TAG=v2.1.84
LIBSSH_TAG=libssh-0.9.6
LIBNETCONF2_TAG=v2.1.18
NETOPEER2_TAG=v2.1.36
clone-deps:
	$(MAKE) clone-or-update REPOSITORY=https://github.com/CESNET/libyang.git BRANCH=$(LIBYANG_TAG)
	$(MAKE) clone-or-update REPOSITORY=https://github.com/sysrepo/sysrepo.git BRANCH=$(SYSREPO_TAG)
	$(MAKE) clone-or-update REPOSITORY=http://git.libssh.org/projects/libssh.git BRANCH=$(LIBSSH_TAG)
	$(MAKE) clone-or-update REPOSITORY=https://github.com/CESNET/libnetconf2.git BRANCH=$(LIBNETCONF2_TAG)
	$(MAKE) clone-or-update REPOSITORY=https://github.com/CESNET/netopeer2.git BRANCH=$(NETOPEER2_TAG)

# BuildKit speeds up the image builds by running independent stages in a
# multi-stage Dockerfile concurrently. BuildKit is a breeze to use with Docker -
# everything just works automagically when you set the env var. The process is a
# bit more involved when using Podman so we are currently only using BuildKit on
# Docker.
build: export DOCKER_BUILDKIT=1
# The standardized OCI image spec does not store the healthcheck in image
# metadata, so there is no support for the HEALTHCHECK directive in the
# Dockerfile. We can use the "docker" image spec with Podman.
build: export BUILDAH_FORMAT=docker
build:
# We explicitly build the first 'build-tools-source' stage (where the
# dependencies are installed and source code is pulled), which allows us to
# control caching of it through the DOCKER_BUILD_CACHE_ARG.
	$(CONTAINER_RUNTIME) build --target build-tools-source $(DOCKER_BUILD_CACHE_ARG) .
	$(CONTAINER_RUNTIME) build --target notconf-release -t $(IMAGE_PATH)notconf:$(DOCKER_TAG) --build-arg BUILD_TYPE=Release .
	$(CONTAINER_RUNTIME) build --target notconf-debug -t $(IMAGE_PATH)notconf:$(DOCKER_TAG)-debug --build-arg BUILD_TYPE=Debug .

tag-release:
	$(CONTAINER_RUNTIME) tag $(IMAGE_PATH)notconf:$(DOCKER_TAG) $(IMAGE_PATH)notconf:latest
	$(CONTAINER_RUNTIME) tag $(IMAGE_PATH)notconf:$(DOCKER_TAG)-debug $(IMAGE_PATH)notconf:debug

push-release:
	$(CONTAINER_RUNTIME) push $(IMAGE_PATH)notconf:debug
	$(CONTAINER_RUNTIME) push $(IMAGE_PATH)notconf:latest

push:
	$(CONTAINER_RUNTIME) push $(IMAGE_PATH)notconf:$(DOCKER_TAG)
	$(CONTAINER_RUNTIME) push $(IMAGE_PATH)notconf:$(DOCKER_TAG)-debug

test: export CNT_PREFIX=test-notconf-$(PNS)
test:
	-$(CONTAINER_RUNTIME) rm -f $(CNT_PREFIX)
# Usually we would start the notconf container with the desired YANG module
# (located on host) mounted to /yang-modules (in container). When the test
# itself is executed in a (CI runner) container bind mounting a path won't work
# because the path does not exist on the host, only in the test container. As a
# workaround we first create the container and then copy the YANG module to the
# target location.
#	docker run -d --name $(CNT_PREFIX) -v $$(pwd)/test:/yang-modules $(IMAGE_PATH)notconf:$(DOCKER_TAG)
	$(CONTAINER_RUNTIME) create --name $(CNT_PREFIX) $(IMAGE_PATH)notconf:$(DOCKER_TAG)
	$(CONTAINER_RUNTIME) cp test/test.yang $(CNT_PREFIX):/yang-modules/
	$(CONTAINER_RUNTIME) cp test/test.xml $(CNT_PREFIX):/yang-modules/
	$(CONTAINER_RUNTIME) start $(CNT_PREFIX)
	$(MAKE) wait-healthy
	$(CONTAINER_RUNTIME) run -i --rm --network container:$(CNT_PREFIX) $(IMAGE_PATH)notconf:$(DOCKER_TAG)-debug netconf-console2 --port 830 --get-config -x /bob/startup | grep Robert
	$(CONTAINER_RUNTIME) run -i --rm --network container:$(CNT_PREFIX) $(IMAGE_PATH)notconf:$(DOCKER_TAG)-debug netconf-console2 --port 830 --ns test=urn:notconf:test --set /test:bob/test:bert=Robert
	$(CONTAINER_RUNTIME) run -i --rm --network container:$(CNT_PREFIX) $(IMAGE_PATH)notconf:$(DOCKER_TAG)-debug netconf-console2 --port 830 --get-config -x /bob/bert | grep Robert
	$(MAKE) save-logs
	$(MAKE) test-stop

test-stop: CNT_PREFIX?=test-notconf
test-stop:
	$(CONTAINER_RUNTIME) ps -aqf name=$(CNT_PREFIX) | xargs --no-run-if-empty docker rm -f

# This test exports the images we built with Podman to Docker and then runs the
# test suite in Docker. Obviously both container runtimes must be installed on
# the machine.
test-podman-to-docker:
	podman save $(IMAGE_PATH)notconf:$(DOCKER_TAG) | docker load
	podman save $(IMAGE_PATH)notconf:$(DOCKER_TAG)-debug | docker load
	CONTAINER_RUNTIME=docker $(MAKE) test

save-logs: CNT_PREFIX?=test-notconf
save-logs:
	mkdir -p container-logs
	@for c in $$($(CONTAINER_RUNTIME) ps -af name=$(CNT_PREFIX) --format '{{.Names}}'); do \
		echo "== Collecting logs from $${c}"; \
		$(CONTAINER_RUNTIME) logs $${c} > container-logs/$${c} 2>&1; \
	done

SHELL=/bin/bash

wait-healthy:
	@echo "Waiting (up to 900 seconds) for containers with prefix $(CNT_PREFIX) to become healthy"
	@OLD_COUNT=0; for I in $$(seq 1 900); do \
		COUNT=$$($(CONTAINER_RUNTIME) ps -f name=$(CNT_PREFIX) | egrep "(unhealthy|health: starting)" | wc -l); \
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
	$(CONTAINER_RUNTIME) ps -f name=$(CNT_PREFIX) | egrep "(unhealthy|health: starting)" | awk '{ print $$(NF) }';\
	echo -e "\e[0m"; \
	exit 1
