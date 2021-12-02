FROM ubuntu:latest as builder
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -qy git ca-certificates cmake libpcre2-dev clang \
 # required for testing sysrepo
 && apt-get install -qy libcmocka-dev valgrind

RUN git clone -b devel https://github.com/CESNET/libyang.git
RUN git clone -b devel https://github.com/sysrepo/sysrepo.git
RUN git clone -b stable-0.9 http://git.libssh.org/projects/libssh.git
RUN git clone -b devel https://github.com/CESNET/libnetconf2.git
RUN git clone -b devel https://github.com/CESNET/netopeer2.git

WORKDIR /libyang
RUN mkdir build && \
  cd build && \
  cmake -D CMAKE_BUILD_TYPE:String="Release" .. && \
  make -j && \
  make install

WORKDIR /sysrepo
RUN mkdir build && \
  cd build && \
  cmake -D CMAKE_BUILD_TYPE:String="Release" -D ENABLE_TESTS=ON .. && \
  make -j && \
  make test && \
  make install

RUN apt-get install -qy zlib1g-dev libssl-dev
WORKDIR /libssh
RUN mkdir build && \
  cd build && \
  cmake -D CMAKE_BUILD_TYPE:String="Release" .. && \
  make -j && \
  make install

WORKDIR /libnetconf2
RUN mkdir build && \
  cd build && \
  cmake -D CMAKE_BUILD_TYPE:String="Release" .. && \
  make -j && \
  make install

WORKDIR /netopeer2
RUN mkdir build && \
  cd build && \
  cmake -D CMAKE_BUILD_TYPE:String="Release" .. && \
  make -j && \
  ldconfig && \
  make install

FROM ubuntu:latest
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

COPY run.sh /
COPY load-yang-modules.sh /

ENV EDITOR=vim
ENV YANG_MODULES_DIR=/yang-modules
EXPOSE 830

ENTRYPOINT /run.sh
