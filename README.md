# notconf

notconf is a NETCONF device simulator based on [Netopeer2] and [sysrepo] running
in a container. A simulator in this case is a NETCONF server that exposes the
standard NETCONF management interface of the simulated device without actually
performing and (network) functions.

The intended use is to provide a light-weight device for testing network
automation systems that produce configuration or otherwise interface with the
device over NETCONF. The simulated device consumes few resources in contrast
with creating a complete virtual machine (router).

If you are familiar with Cisco NSO, notconf is a drop-in replacement for netsim.
The advantages of notconf over netsim are:
- notconf is open source and based on open source software
- building a custom image with custom (vendor) YANG modules is easy and faster
  than with netsim (no YANG compilation required)

[Netopeer2]: https://github.com/CESNET/Netopeer2
[sysrepo]: https://github.com/sysrepo/sysrepo

## Usage

### Prerequisites

For running the container from a pre-built image the only prerequisite is Docker
or some other container runtime like Podman. Building the base and custom images
further requires make, git and xmlstarlet and optionally netconf-console2 for
NETCONF operations testing. netconf-console2 is also installed in the
notconf:debug image for convenience. For an definitive list check the GitHub
action workflow for the `build-notconf-base`.

### Start a container with custom YANG modules

The base container image `notconf:latest` contains the Netopeer2 installation with
all of its runtime dependencies. The set of YANG modules included in the NETCONF
server is the bare minimum to make Netopeer2 work. This is enough for any
NETCONF client to establish a NETCONF session, but not much else. You will most
likely want to include your own or vendor YANG modules to simulate a network
device. In the following example we will use the `test.yang` YANG module
included in this repository in the `test` directory. The vanilla notconf image
will load all YANG modules found in the `/yang-modules` directory inside the
container. Therefore the quickest way to use custom modules is to bind mount a
host directory to the `/yang-modules` directory in the container.

Yang modules could also contain optional features that, by default, are disabled.
At startup the container will look for the file `/yang-modules/enable-features.csv`
to determine if some features should be enabled. Each row of the file should start
with a module name followed by comma and the name of a feature to enable,
one pair per line.

``` shell
# start the container and bind mount the `test` directory to `/yang-modules`
❯ docker run -d --rm --name notconf-test -v $(pwd)/test/yang-modules:/yang-modules notconf
# verify the NETCONF server supports the test YANG module
# with netconf-console2 installed on your local machine:
❯ netconf-console2 --host $(docker inspect notconf-test --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}') --port 830 --get /modules-state
# or run netconf-console2 from the notconf:debug image:
❯ docker run -i --network container:notconf-test ghcr.io/notconf/notconf:debug netconf-console2 --port 830 --get /modules-state
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
❯ docker build -f Dockerfile.yang -t notconf-test --build-arg COMPOSE_PATH=test/yang-modules .
Sending build context to Docker daemon
Step 1/9 : ARG IMAGE_PATH
Step 2/9 : ARG IMAGE_TAG=latest
Step 3/9 : FROM ${IMAGE_PATH}notconf:${IMAGE_TAG} AS notconf-install
 ---> 62b1b5b48905
Step 4/9 : ARG COMPOSE_PATH
 ---> Running in 9cf6b8d26422
Removing intermediate container 9cf6b8d26422
...
Successfully built 5abbdafc0f9a
Successfully tagged notconf-test:latest

# start the container with the composed image and verify the test.yang module is present
❯ docker run -d --rm --name notconf-test -v $(pwd)/test:/yang-modules notconf
❯ docker run -i --rm --network container:notconf-test ghcr.io/notconf/notconf:debug netconf-console2 --port 830 --get -x '/modules-state/module[name="test"]'
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
- `IMAGE_PATH`: prefix to the base notconf container image, like `ghcr.io/notconf/notconf`, defaults to empty string
- `IMAGE_TAG`: suffix to the base notconf container image, defaults to `latest`

### Compose a custom notconf image with vendor YANG modules

YANG modules for several network devices from different vendors can be found in
the public [YangModels/yang] repository. The majority of the modules are valid
YANG 1.1 modules, but there are some tweaks that need to be made in order for
sysrepo to accept them. This repository contains "fixup" Makefiles for the
platforms:
- nokia/sros
- juniper/junos
- cisco/xr

[YangModels/yang]: https://github.com/YangModels/yang

### Mocking startup and operational datastore

In addition to the obvious NETCONF interface for modifying the running
configuration, notconf also allows users to modify startup configuration and
operational (config false) data.

#### Startup configuration

Any XML files placed in the `/yang-modules/startup` directory in the container
will be automatically imported into the startup datastore when the notconf
container starts. When all files are imported the startup datastore is copied to
running. The XML files must conform to YANG models loaded and *must not*
contain operational data.

#### Operational (config false) data

Any XML files placed in the `/yang-modules/operational` directory in the
container will be automatically imported into the operational datastore when the
notconf container starts, or when any change is detected to this directory. The
XML files must conform to YANG models loaded and *must not* contain configuration
data.

To update operational data in a running notconf container just update one of the
files! When a change is detected all XMLs are sorted by filename and then loaded
in order. The time to load operational data depends on the set of installed YANG
modules and the amount of operational data provided in XMLs. If you want to
ensure your test scripts do not proceed with test before all operational data is
ready, you can execute the `/wait-operational-sync.sh` script in the container.
The script will block until the process is complete.

```shell
# start the container and bind mount the `test` directory to `/yang-modules`
❯ docker run -d --rm --name notconf-test -v $(pwd)/test/yang-modules:/yang-modules notconf
# verify operational data in test/yang-modules/operational/test-oper.xml is present
❯ docker run -i --network container:notconf-test ghcr.io/notconf/notconf:debug netconf-console2 --port 830 --get -x /bob
<?xml version='1.0' encoding='UTF-8'?>
<data xmlns="urn:ietf:params:xml:ns:netconf:base:1.0">
  <bob xmlns="urn:notconf:test">
    <startup>Robert!</startup>
    <state>
      <great>success</great>
    </state>
  </bob>
</data>
# now you can modify the files in test/yang-modules/operational and observe the changes
#
# for test scripts, if you want to make sure operational data update is done, use the wait-operational-sync.sh script
❯ docker exec notconf-test /wait-operational-sync.sh
Triggering operational data sync
Operational data sync done!
```

## Troubleshooting and development

### Multi-arch support and building

The notconf images, like `notconf` and `notconf:debug`, are manifest tags that
combine the images for multiple architectures. The images are built for the
following platforms:
- linux/amd64, arch x86_64: ghcr.io/notconf/notconf:latest-x86_64
- linux/arm64, arch aarch64: ghcr.io/notconf/notconf:latest-aarch64

This means you can use the notconf images from the public registry natively on
the supported platforms. For example, on MacOS running on Apple silicon, using
the `ghcr.io/notconf/notconf:latest` image tag will transparently pull the
`ghcr.io/notconf/notconf:latest-aarch64` image.

The same holds true for the composed images containing vendor YANG modules. The
version tagged image, like `notconf-junos:21.2R1`, is a manifest tag that
combines the images for the supported architectures.

```shell
❯ docker run -it --rm ghcr.io/notconf/notconf:latest uname -m
aarch64
```

If you start a local build, only a single image architecture - that of the build
host, will be built. In CI we build the multi-arch images on the native platform
hardware, i.e. for x86_64 we use the `ubuntu-24.04` runners and for aarch64 we
use `ubuntu-24.04-arm`.

Building a local development image is as simple as ensuring you have installed
the build prerequisites and running the make recipes:

```shell
# get the dependencies
❯ make clone-deps
# build the base images
❯ make build
```

## WIP and planned work

- [ ] Automatically build composed images for more platforms (+ versions)

### Debugging sysrepo and Netopeer2

All the heavy lifting of providing a NETCONF server is done by Netopeer2 and
sysrepo, so this repository does not contain much code. The base notconf image
includes the dependencies compiled with the "Release" option. If you need to
troubleshoot some behavior of the NETCONF server it may be beneficial to use the
binaries compiled with the "Debug" options. The `notconf:debug` image is
automatically built and tagged in the build process.
