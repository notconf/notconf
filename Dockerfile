FROM ubuntu:latest AS build-tools-source
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -qy ca-certificates cmake libpcre2-dev clang \
 # required for testing sysrepo
 && apt-get install -qy libcmocka-dev valgrind \
 # libssh dependencies
 && apt-get install -qy zlib1g-dev libssl-dev \
 # libnetconf2 now supports PAM
 && apt-get install -qy libpam0g-dev \
 # common sense tools for debugging
 && apt-get install -qy less neovim git

COPY /src /src

FROM build-tools-source AS builder
ARG BUILD_TYPE

WORKDIR /src/libyang
RUN mkdir build && \
  cd build && \
  cmake -D CMAKE_BUILD_TYPE:String=${BUILD_TYPE} .. && \
  make -j && \
  make install

WORKDIR /src/sysrepo
RUN mkdir build && \
  cd build && \
  # Explicitly set REPO_PATH for Debug builds
  cmake -D CMAKE_BUILD_TYPE:String=${BUILD_TYPE} -D REPO_PATH=/etc/sysrepo .. && \
  make -j && \
  make install

WORKDIR /src/libssh
RUN mkdir build && \
  cd build && \
  cmake -D CMAKE_BUILD_TYPE:String=${BUILD_TYPE} .. && \
  make -j && \
  make install

WORKDIR /src/libnetconf2
RUN mkdir build && \
  cd build && \
  cmake -D CMAKE_BUILD_TYPE:String=${BUILD_TYPE} .. && \
  make -j && \
  make install

WORKDIR /src/netopeer2
RUN mkdir build && \
  cd build && \
  cmake -D CMAKE_BUILD_TYPE:String=${BUILD_TYPE} .. && \
  make -j && \
  ldconfig && \
  make install

FROM ubuntu:latest as notconf-release
LABEL org.opencontainers.image.source="https://github.com/mzagozen/notconf"
LABEL org.opencontainers.image.description="This is the release build of notconf. Start the container with the device YANG modules mounted to /yang-modules to simulate the NETCONF management interface."
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -qy libssl-dev \
 && apt-get -qy autoremove \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /root/.cache

COPY --from=builder /usr/local /usr/local
COPY --from=builder /etc/sysrepo /etc/sysrepo
RUN ldconfig

RUN adduser --system netconf \
 && adduser --system admin \
 && echo "netconf:netconf" | chpasswd \
 && echo "admin:admin" | chpasswd

COPY disable-nacm.xml /
RUN sysrepocfg --edit=disable-nacm.xml -d startup --module ietf-netconf-acm -v4

COPY *.sh /
RUN mkdir /yang-modules

ENV YANG_MODULES_DIR=/yang-modules
EXPOSE 830

CMD /run.sh
HEALTHCHECK --start-period=30s --interval=5s CMD grep -e 'Listening on .* for SSH connections' /log/netopeer.log

FROM builder as notconf-debug
LABEL org.opencontainers.image.source="https://github.com/mzagozen/notconf"
LABEL org.opencontainers.image.description="This is the debug build of notconf - the server (netopeer2) and its dependencies (sysrepo, libnetconf2, libyang) are built with the debug flag set. The image also includes a compiler (clang) and debugging tools (gdb and valgrind). Start the container with the device YANG modules mounted to /yang-modules to simulate the NETCONF management interface."

RUN apt-get install -qy python3-pip \
 && pip3 install netconf-console2 \
 && apt-get -qy remove python3-pip \
 && apt-get -qy autoremove \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* /root/.cache

RUN adduser --system netconf \
 && adduser --system admin \
 && echo "netconf:netconf" | chpasswd \
 && echo "admin:admin" | chpasswd

COPY disable-nacm.xml /
RUN sysrepocfg --edit=disable-nacm.xml -d startup --module ietf-netconf-acm -v4

COPY *.sh /
RUN mkdir /yang-modules

ENV EDITOR=vim
ENV YANG_MODULES_DIR=/yang-modules
EXPOSE 830

CMD /run.sh
HEALTHCHECK --start-period=30s --interval=5s CMD grep -e 'Listening on .* for SSH connections' /log/netopeer.log
