# syntax=docker/dockerfile:1
# Quartus Prime Lite 17.0.2 (Cyclone V) for building MiSTer cores.
#
# Put Quartus-lite-17.0.2.602-linux.tar (from Intel's download centre) in this
# directory, then:  docker build -t mister-quartus17 tools/quartus-docker
#
# The installer is bind-mounted, not copied, so the ~6 GB tar never ends up in
# an image layer. Based on github.com/ebraminio/mister-docker-build (MIT).
#
# Debian jessie on purpose: Quartus 17.0 is from 2017 and crashes in
# quartus_map on newer distributions (libudev).

FROM debian:jessie

RUN echo "deb [check-valid-until=no] http://archive.debian.org/debian jessie main" > /etc/apt/sources.list && \
    echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/100disablechecks && \
    apt-get update && \
    apt-get -y --force-yes install expect locales libtcmalloc-minimal4 libglib2.0-0 && \
    echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && locale-gen en_US.UTF-8 && \
    rm -rf /var/lib/apt/lists/*

COPY install_quartus.exp /tmp/install_quartus.exp

RUN --mount=type=bind,source=Quartus-lite-17.0.2.602-linux.tar,target=/tmp/quartus.tar \
    mkdir -p /tmp/quartus && tar xf /tmp/quartus.tar -C /tmp/quartus && \
    expect /tmp/install_quartus.exp 17.0 && \
    rm -rf /tmp/quartus /tmp/install_quartus.exp && \
    test -x /opt/intelFPGA_lite/17.0/quartus/bin/quartus_sh

ENV LANG=en_US.UTF-8 \
    PATH=/opt/intelFPGA_lite/17.0/quartus/bin:$PATH

WORKDIR /build
