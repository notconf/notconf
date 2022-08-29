# notconf

notconf is a NETCONF device simulator based on [Netopeer2] and [sysrepo] running
in a container. A simulator in this case is a NETCONF server that exposes the
standard NETCONF management interface of the simulated device without actually
performing and (network) functions.

The intended use is to provide a light-weight device for testing network
automation systems that produce configuration or otherwise interface with the
device over NETCONF. The simulated device consumes few resources in contrast
with creating a complete virtual machine (router).

[Netopeer2]: https://github.com/CESNET/Netopeer2
[sysrepo]: https://github.com/sysrepo/sysrepo

## Usage

### Prerequisites

For running the container from a pre-built image the only prerequisite is docker
or some other container runtime. Building the base and custom images further
requires make, git and xmlstarlet and optionally netconf-console2 for NETCONF
operations testing. For an definitive list check the GitHub action workflow for
the `build-notconf-base`.

### Start a container with custom YANG modules

The base docker image `notconf:latest` contains the Netopeer2 installation with
all of its runtime dependencies. The set of YANG modules included in the NETCONF
server is the bare minimum to make Netopeer2 work. This is enough for any
NETCONF client to establish a NETCONF session, but not much else. You will most
likely want to include your own or vendor YANG modules to simulate a network
device. In the following example we will use the `test.yang` YANG module
included in this repository in the `test` directory. The vanilla notconf image
will load all YANG modules found in the `/yang-modules` directory inside the
container. Therefore the quickest way to use custom modules is to bind mount a
host directory to the `/yang-modules` directory in the container.

``` shell
# start the container and bind mount the `test` directory to `/yang-modules`
❯ docker run -d --rm --name notconf-test -v $(pwd)/test:/yang-modules notconf
# verify the NETCONF server supports the test YANG module
❯ netconf-console2 --host $(docker inspect notconf-test --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}') --port 830 --get /modules-state
...
    <module>
      <name>test</name>
      <revision/>
      <schema>file:///etc/sysrepo/yang/test.yang</schema>
      <namespace>urn:notconf:test</namespace>
      <conformance-type>implement</conformance-type>
    </module>
  </modules-state>
</data>
```

### Compose a custom notconf image with custom YANG modules

You may notice that startup times for the notconf container vary depending on
the number and complexity of loaded YANG modules. The majority of the time in
the startup script is spent installing the YANG modules with sysrepoctl. This
can be optimized though by building a custom notconf image where the modules are
instead installed at image build time.

In the next example we will build a notconf image that includes the `test.yang`
module. The `Dockerfile.yang` file is a multi-stage file that first installs the
modules in found in the path configured with the `COMPOSE_PATH` build argument,
then copies the results to a clean image.

``` shell
# build the custom notconf-test image
❯ docker build -f Dockerfile.yang -t notconf-test --build-arg COMPOSE_PATH=test .
Sending build context to Docker daemon
Step 1/9 : ARG IMAGE_PATH
Step 2/9 : ARG DOCKER_TAG=latest
Step 3/9 : FROM ${IMAGE_PATH}notconf:${DOCKER_TAG} AS notconf-install
 ---> 62b1b5b48905
Step 4/9 : ARG COMPOSE_PATH
 ---> Running in 9cf6b8d26422
Removing intermediate container 9cf6b8d26422
...
Successfully built 5abbdafc0f9a
Successfully tagged notconf-test:latest

# start the container with the composed image and verify the test.yang module is present
❯ docker run -d --rm --name notconf-test -v $(pwd)/test:/yang-modules notconf
❯ netconf-console2 --host $(docker inspect notconf-test --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}') --port 830 --get -x '/modules-state/module[name="test"]'
<?xml version='1.0' encoding='UTF-8'?>
<data xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
  <modules-state xmlns="urn:ietf:params:xml:ns:yang:ietf-yang-library">
    <module>
      <name>test</name>
      <revision/>
      <schema>file:///etc/sysrepo/yang/test.yang</schema>
      <namespace>urn:notconf:test</namespace>
      <conformance-type>implement</conformance-type>
    </module>
  </modules-state>
</data>
```

Note: `Dockerfile.yang` has two additional optional build arguments:
- `IMAGE_PATH`: prefix to the base notconf docker image, like `registry.example.org/notconf`, defaults to empty string
- `DOCKER_TAG`: suffix to the base notconf docker image, defaults to `latest`

### Compose a custom notconf image with vendor YANG modules

YANG modules for several network devices from different vendors can be found in
the public [YangModels/yang] repository. The majority of the modules are valid
YANG 1.1 modules, but there are some tweaks that need to be made in order for
sysrepo to accept them. This repository contains "fixup" Makefiles for the
platforms:
- nokia/sros
- juniper/junos
- cisco/xr (still a work in progress)

[YangModels/yang]: https://github.com/YangModels/yang

## Troubleshooting and development

## WIP and planned work

- [ ] Build a notconf image with YANG models for Cisco IOS XR
  - Installation of YANG models from the [YangModels] repository works, but
    after loading certain (complex?) models the installation process slows down
    significantly - installing each file *after* takes longer (4s+).
  - `%Cisco-IOS-XR-ipv4-bgp-oper.yang %Cisco-IOS-XR-ipv4-bgp-oc-oper.yang` for
    example trigger this. Need to investigate and report upstream to see if
    sysrepo can be improved??

### Debugging sysrepo and Netopeer2

All the heavy lifting of providing a NETCONF server is done by Netopeer2 and
sysrepo, so this repository does not contain much code. The base notconf image
includes the dependencies compiled with the "Release" option. If you need to
troubleshoot some behavior of the NETCONF server it may be beneficial to use the
binaries compiled with the "Debug" options. The `notconf:debug` image is
automatically built and tagged in the build process.
