ARG BUILD_TYPE

FROM ubuntu:latest AS git
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -qy git

FROM git AS git-clone
WORKDIR /src
RUN git clone -b devel https://github.com/CESNET/libyang.git
RUN git clone -b devel https://github.com/sysrepo/sysrepo.git
RUN git clone -b stable-0.9 http://git.libssh.org/projects/libssh.git
RUN git clone -b devel https://github.com/CESNET/libnetconf2.git
RUN git clone -b devel https://github.com/CESNET/netopeer2.git

FROM git AS build-tools
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get install -qy ca-certificates cmake libpcre2-dev clang \
 # required for testing sysrepo
 && apt-get install -qy libcmocka-dev valgrind \
 # libssh dependencies
 && apt-get install -qy zlib1g-dev libssl-dev \
 # common sense tools for debugging
 && apt-get install -qy less vim

FROM build-tools AS build-tools-source
COPY --from=git-clone /src /src

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

ENV EDITOR=vim
ENV YANG_MODULES_DIR=/yang-modules
EXPOSE 830

ENTRYPOINT /run.sh
HEALTHCHECK CMD grep -e 'Listening on .* for SSH connections' /log/netopeer.log

FROM builder as notconf-debug
LABEL org.opencontainers.image.source="https://github.com/mzagozen/notconf"
LABEL org.opencontainers.image.description="This is the debug build of notconf - the server (netopeer2) and its dependencies (sysrepo, libnetconf2, libyang) are built with the debug flag set. The image also includes a compiler (clang) and debugging tools (gdb and valgrind). Start the container with the device YANG modules mounted to /yang-modules to simulate the NETCONF management interface."

RUN adduser --system netconf \
 && adduser --system admin \
 && echo "netconf:netconf" | chpasswd \
 && echo "admin:admin" | chpasswd

COPY disable-nacm.xml /
RUN sysrepocfg --edit=disable-nacm.xml -d startup --module ietf-netconf-acm -v4

COPY *.sh /

ENV EDITOR=vim
ENV YANG_MODULES_DIR=/yang-modules
EXPOSE 830

ENTRYPOINT /run.sh
HEALTHCHECK CMD grep -e 'Listening on .* for SSH connections' /log/netopeer.log
