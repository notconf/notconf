CONTAINER_RUNTIME ?= docker

test-netconf: test-netconf.go
	go build -o $@ $<

build-container-image: Dockerfile
	$(CONTAINER_RUNTIME) build -t test-netconf .