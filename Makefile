IMAGE_PATH?=$(call lc,$(CI_REGISTRY)/$(CI_PROJECT_NAMESPACE)/)

ifneq ($(CI_PIPELINE_ID),)
PNS:=$(CI_PIPELINE_ID)
else
PNS:=$(shell whoami | sed 's/[^[:alnum:]._-]\+/_/g')
endif

DOCKER_TAG?=$(PNS)

.PHONY: build test tag-release push-release push test

build: export DOCKER_BUILDKIT=1
build:
	docker build --target notconf-release -t $(IMAGE_PATH)notconf:$(DOCKER_TAG) --build-arg BUILD_TYPE=Release .
	docker build --target notconf-debug -t $(IMAGE_PATH)notconf:$(DOCKER_TAG)-debug --build-arg BUILD_TYPE=Debug .

tag-release:
	docker tag $(IMAGE_PATH)notconf:$(DOCKER_TAG) $(IMAGE_PATH)notconf:latest
	docker tag $(IMAGE_PATH)notconf:$(DOCKER_TAG)-debug $(IMAGE_PATH)notconf:debug

push-release:
	docker push $(IMAGE_PATH)notconf:latest
	docker push $(IMAGE_PATH)notconf:debug

push:
	docker push $(IMAGE_PATH)notconf:$(DOCKER_TAG)
	docker push $(IMAGE_PATH)notconf:$(DOCKER_TAG)-debug

test:
	-docker rm -f test-notconf-$(PNS)
	docker run -d --name test-notconf-$(PNS) -v $$(pwd)/test/test.yang:/yang-modules/test.yang $(IMAGE_PATH)notconf:$(DOCKER_TAG)
	netconf-console --host $$(docker inspect test-notconf-$(PNS) --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}') --port 830 --edit-config test/test.xml
	netconf-console --host $$(docker inspect test-notconf-$(PNS) --format='{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}') --port 830 --get-config -x /bob/bert | grep Robert
	docker rm -f test-notconf-$(PNS)
