# SPDX-FileCopyrightText: © 2025 VEXXHOST, Inc.
# SPDX-License-Identifier: Apache-2.0

ARG FROM=debian:13.1@sha256:fd8f5a1df07b5195613e4b9a0b6a947d3772a151b81975db27d47f093f60c6e6

FROM rust:1.90 AS ovsinit
ARG ATMOSPHERE_REF=655208f1b53ab75c36864ed71dc543c30e21bd53
ADD https://github.com/vexxhost/atmosphere.git#${ATMOSPHERE_REF} /src/ovsinit
WORKDIR /src/ovsinit/crates/ovsinit
RUN cargo install --path .

FROM runtime
COPY --from=builder /usr/local/cargo/bin/ovsinit /usr/local/bin/ovsinit

FROM golang:1.21 AS ovn-kubernetes
RUN apt-get update && \
    apt-get install --no-install-recommends -y \
        quilt
ARG OVN_KUBERNETES_REF=5359e7d7f872058b6e5bf884c9f19d1922451f29
ADD https://github.com/ovn-kubernetes/ovn-kubernetes.git#${OVN_KUBERNETES_REF} /src/ovn-kubernetes
WORKDIR /src/ovn-kubernetes
COPY patches/ovn-kubernetes /patches
RUN --network=none \
    QUILT_PATCHES=/patches \
    QUILT_PC=/src/.pc \
    QUILT_PATCH_OPTS="--unified -p1" \
    quilt push -a --fuzz=0 --leave-rejects
WORKDIR /src/ovn-kubernetes/go-controller
RUN go build -o /ovn-kube-util ./cmd/ovn-kube-util

FROM ${FROM} AS ovn
RUN apt-get update && \
    apt-get install --no-install-recommends -y \
        autoconf \
        automake \
        libcap-ng-dev \
        libssl-dev \
        libtool \
        libunbound-dev \
        make \
        openssl \
        python3
ARG OVN_COMMIT=f82b6d141f7988a45fcf2c2a722f0a6d0a1b02b7
ADD https://github.com/ovn-org/ovn.git#${OVN_COMMIT} /src/ovn
WORKDIR /src/ovn/ovs
RUN --network=none ./boot.sh
RUN --network=none \
    ./configure \
        --prefix=/usr \
        --localstatedir=/var \
        --sysconfdir=/etc
RUN --network=none make -j$(nproc)
WORKDIR /src/ovn
RUN --network=none ./boot.sh
RUN --network=none \
    ./configure \
        --prefix=/usr \
        --localstatedir=/var \
        --sysconfdir=/etc
RUN --network=none make -j$(nproc)
# RUN --network=none make check TESTSUITEFLAGS=-j$(nproc)
RUN --network=none make install DESTDIR=/out/ovn

FROM ${FROM}
RUN groupadd -r -g 42424 openvswitch && \
    useradd -r -g openvswitch -u 42424 openvswitch
RUN apt-get update && \
    apt-get install --no-install-recommends -y \
        libunbound8 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
COPY --from=ovn-kubernetes /src/ovn-kubernetes/dist/images/ovndb-raft-functions.sh /root/ovndb-raft-functions.sh
COPY --from=ovn-kubernetes /src/ovn-kubernetes/dist/images/ovnkube.sh /root/ovnkube.sh
COPY --from=ovn-kubernetes /ovn-kube-util /usr/bin/ovn-kube-util
COPY --from=ovsinit /usr/local/cargo/bin/ovsinit /usr/local/bin/ovsinit
COPY --from=ovn /out/ovn /
