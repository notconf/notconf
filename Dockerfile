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
 # rousette requires doxygen
 # TODO: remove this dependency from rousette CMakeLists.txt
RUN apt-get install -qy doxygen graphviz \
 && apt-get install -qy libspdlog-dev
RUN apt-get install -qy libboost-all-dev libnghttp2-dev
RUN apt-get install -qy libdocopt-dev

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

WORKDIR /src/libyang-cpp
RUN cmake -B build -D CMAKE_BUILD_TYPE:String=${BUILD_TYPE} -D BUILD_TESTING=OFF -D WITH_DOCS=OFF && \
  make -C build -j && \
  make -C build install

WORKDIR /src/sysrepo-cpp
RUN cmake -B build -D CMAKE_BUILD_TYPE:String=${BUILD_TYPE} -D BUILD_TESTING=OFF -D WITH_DOCS=OFF && \
  make -C build -j && \
  make -C build install

WORKDIR /src/nghttp2-asio
RUN cmake -B build -D CMAKE_BUILD_TYPE:String=${BUILD_TYPE} && \
  make -C build -j && \
  make -C build install

WORKDIR /src/date
RUN cmake -B build -D CMAKE_BUILD_TYPE:String=${BUILD_TYPE} -D BUILD_TZ_LIB=ON && \
  make -C build -j && \
  make -C build install

WORKDIR /src/rousette
RUN cmake -B build -D CMAKE_BUILD_TYPE:String=${BUILD_TYPE} -D BUILD_TESTING=OFF && \
  make -C build -j && \
  make -C build install

# Install rousette YANG modules into sysrepo
RUN for yang in /src/rousette/yang/*.yang; do \
    echo "Installing YANG module: $(basename $yang)" && \
    sysrepoctl -i "$yang" -v4 || exit 1; \
  done

WORKDIR /

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
# rousette runtime dependencies - only install specific boost libs needed
 && apt-get install -qy libpam0g libspdlog1.12 \
    libboost-system1.83.0 libboost-thread1.83.0 libboost-atomic1.83.0 \
    libdocopt0 \
# HTTP/2 proxy for rousette
 && apt-get install -qy nghttp2-proxy \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /root/.cache

COPY disable-nacm.xml /
RUN sysrepocfg --edit=/disable-nacm.xml -d startup --module ietf-netconf-acm -v4

COPY admin.xml /
RUN sysrepocfg --edit=/admin.xml -d startup --module ietf-netconf-server -v4

# rousette authenticates via pam so we need a system user
# create admin group and user for nacm access control
run groupadd admin \
 && useradd --no-create-home -s /usr/sbin/nologin -g admin admin \
 && echo "admin:admin" | chpasswd

COPY *.sh /
COPY load-oper-data.py /
RUN mkdir /yang-modules

ENV YANG_MODULES_DIR=/yang-modules
EXPOSE 80 830

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
# HTTP/2 proxy for rousette and curl for testing
 && apt-get install -qy nghttp2-proxy curl \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /root/.cache

COPY disable-nacm.xml /
RUN sysrepocfg --edit=/disable-nacm.xml -d startup --module ietf-netconf-acm -v4

COPY admin.xml /
RUN sysrepocfg --edit=/admin.xml -d startup --module ietf-netconf-server -v4

# rousette authenticates via pam so we need a system user
# create admin group and user for nacm access control
run groupadd admin \
 && useradd --no-create-home -s /usr/sbin/nologin -g admin admin \
 && echo "admin:admin" | chpasswd

COPY *.sh /
COPY load-oper-data.py /
RUN mkdir /yang-modules

ENV EDITOR=vim
ENV YANG_MODULES_DIR=/yang-modules
EXPOSE 80 830

CMD /run.sh
HEALTHCHECK --start-period=30s --interval=5s CMD grep -e 'Listening on .* for SSH connections' /log/netopeer.log
