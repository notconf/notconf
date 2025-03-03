# The build-tools-source stage contains all the build dependencies + the source
# directories in /src. This allows us to cache this stage until the base image
# version changes or we bump the versions of the installed packages.

FROM ubuntu:noble AS build-tools-source
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -qy ca-certificates cmake libpcre2-dev libssh-dev clang \
 # required for testing sysrepo
 && apt-get install -qy libcmocka-dev valgrind \
 # libnetconf2 now supports PAM
 && apt-get install -qy libpam0g-dev \
 # libnetconf2 (devel) now requires curl
 && apt-get install -qy libcurl4-openssl-dev \
 # netopeer2 (devel) now requires pkg-config
 && apt-get install -qy pkg-config \
 # common sense tools for debugging
 && apt-get install -qy less neovim git

COPY /src /src

# The next builder stage builds all the components from source with the
# BUILD_TYPE=(Release|Debug) flag set

FROM build-tools-source AS builder
ARG BUILD_TYPE

WORKDIR /src/libyang
RUN cmake -B build -D CMAKE_BUILD_TYPE:String=${BUILD_TYPE} && \
  make -C build -j && \
  make -C build install

WORKDIR /src/sysrepo
# Explicitly set REPO_PATH for Debug builds
RUN cmake -B build -D CMAKE_BUILD_TYPE:String=${BUILD_TYPE} -D REPO_PATH=/etc/sysrepo && \
  make -C build -j && \
  make -C build install

WORKDIR /src/libnetconf2
RUN cmake -B build -D CMAKE_BUILD_TYPE:String=${BUILD_TYPE} && \
  make -C build -j && \
  make -C build install

WORKDIR /src/netopeer2
RUN cmake -B build -D CMAKE_BUILD_TYPE:String=${BUILD_TYPE} && \
  make -C build -j && \
  ldconfig && \
  make -C build install

# The notconf-release stage starts from an "empty" image and installs only the
# bare minimum required to run the notconf applications. In general Python is
# not required for netopeer or sysrepo, but the current operational data loading
# script is written in Python, so we have to install it.

FROM ubuntu:noble AS notconf-release
LABEL org.opencontainers.image.source="https://github.com/notconf/notconf"
LABEL org.opencontainers.image.description="This is the release build of notconf. Start the container with the device YANG modules mounted to /yang-modules to simulate the NETCONF management interface."
ARG DEBIAN_FRONTEND=noninteractive
ARG SYSREPO_PYTHON_VERSION
ARG LIBYANG_PYTHON_VERSION

COPY --from=builder /usr/local /usr/local
COPY --from=builder /etc/sysrepo /etc/sysrepo
RUN ldconfig

RUN apt-get update \
 && apt-get install -qy libssl-dev \
 && apt-get install -qy libcurl4 \
 && apt-get install -qy python3 inotify-tools python3-pip libpcre2-dev \
# Allow pip to "break" the distro Python for the sake of the sysrepo and libyang Python bindings
 && find /usr/lib/python* -name EXTERNALLY-MANAGED -delete \
 && pip3 install sysrepo==${SYSREPO_PYTHON_VERSION} libyang==${LIBYANG_PYTHON_VERSION} \
 && apt-get -qy remove python3-pip libpcre2-dev \
 && apt-get -qy autoremove \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /root/.cache

COPY disable-nacm.xml /
RUN sysrepocfg --edit=disable-nacm.xml -d startup --module ietf-netconf-acm -v4

COPY admin.xml /
RUN sysrepocfg --edit=admin.xml -d startup --module ietf-netconf-server -v4

COPY *.sh /
COPY load-oper-data.py /
RUN mkdir /yang-modules

ENV YANG_MODULES_DIR=/yang-modules
EXPOSE 830

CMD /run.sh
HEALTHCHECK --start-period=30s --interval=5s CMD grep -e 'Listening on .* for SSH connections' /log/netopeer.log

FROM builder AS notconf-debug
LABEL org.opencontainers.image.source="https://github.com/notconf/notconf"
LABEL org.opencontainers.image.description="This is the debug build of notconf - the server (netopeer2) and its dependencies (sysrepo, libnetconf2, libyang) are built with the debug flag set. The image also includes a compiler (clang) and debugging tools (gdb and valgrind). Start the container with the device YANG modules mounted to /yang-modules to simulate the NETCONF management interface."
ARG SYSREPO_PYTHON_VERSION
ARG LIBYANG_PYTHON_VERSION

RUN apt-get update \
 && apt-get install -qy inotify-tools python3-pip \
# Allow pip to "break" the distro Python for the sake of the sysrepo and libyang Python bindings
 && find /usr/lib/python* -name EXTERNALLY-MANAGED -delete \
# six is not explicitly listed as a dependency of netconf-console2, but is still
# imported?! It used to be provided by ncclient, but they removed Python 2
# support in https://github.com/ncclient/ncclient/pull/607
 && pip3 install six \
 && pip3 install netconf-console2 \
 && pip3 install sysrepo==${SYSREPO_PYTHON_VERSION} libyang==${LIBYANG_PYTHON_VERSION} \
 && apt-get -qy remove python3-pip \
 && apt-get -qy autoremove \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /root/.cache

COPY disable-nacm.xml /
RUN sysrepocfg --edit=disable-nacm.xml -d startup --module ietf-netconf-acm -v4

COPY admin.xml /
RUN sysrepocfg --edit=admin.xml -d startup --module ietf-netconf-server -v4

COPY *.sh /
COPY load-oper-data.py /
RUN mkdir /yang-modules

ENV EDITOR=vim
ENV YANG_MODULES_DIR=/yang-modules
EXPOSE 830

CMD /run.sh
HEALTHCHECK --start-period=30s --interval=5s CMD grep -e 'Listening on .* for SSH connections' /log/netopeer.log
