# SPDX-FileCopyrightText: © 2025 VEXXHOST, Inc.
# SPDX-License-Identifier: Apache-2.0

ARG FROM=debian:13.1@sha256:72547dd722cd005a8c2aa2079af9ca0ee93aad8e589689135feaed60b0a8c08d

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
        python3 \
        quilt
ARG OVN_COMMIT=4fa78fa1f9316f23b138f58e7657030596fb0f9d
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
COPY patches/ovn /patches
RUN --network=none \
    QUILT_PATCHES=/patches \
    QUILT_PC=/src/.pc \
    QUILT_PATCH_OPTS="--unified -p1" \
    quilt push -a --fuzz=0 --leave-rejects
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
ENV OVS_USER_ID=42424
RUN groupadd -r -g 42424 openvswitch && \
    useradd -r -g openvswitch -u 42424 openvswitch
ARG KUBECTL_VERSION=v1.34.1
ARG TARGETPLATFORM
ADD --chmod=755 https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${TARGETPLATFORM}/kubectl /usr/local/bin/kubectl
RUN apt-get update && \
    apt-get install --no-install-recommends -y \
        iproute2 \
        libbpf1 \
        libnuma1 \
        libunbound8 \
        libxdp1 \
        procps && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
COPY --from=ovn-kubernetes /src/ovn-kubernetes/dist/images/ovndb-raft-functions.sh /root/ovndb-raft-functions.sh
COPY --from=ovn-kubernetes /src/ovn-kubernetes/dist/images/ovnkube.sh /root/ovnkube.sh
COPY --from=ovn-kubernetes /ovn-kube-util /usr/bin/ovn-kube-util
COPY --from=ovsinit /usr/local/cargo/bin/ovsinit /usr/local/bin/ovsinit
COPY --from=ghcr.io/vexxhost/openvswitch:latest /usr/bin/ovs-appctl /usr/bin/ovs-appctl
COPY --from=ghcr.io/vexxhost/openvswitch:latest /usr/bin/ovs-ofctl /usr/bin/ovs-ofctl
COPY --from=ghcr.io/vexxhost/openvswitch:latest /usr/bin/ovs-vsctl /usr/bin/ovs-vsctl
COPY --from=ghcr.io/vexxhost/openvswitch:latest /usr/bin/ovsdb-client /usr/bin/ovsdb-client
COPY --from=ghcr.io/vexxhost/openvswitch:latest /usr/bin/ovsdb-tool /usr/bin/ovsdb-tool
COPY --from=ghcr.io/vexxhost/openvswitch:latest /usr/share/openvswitch/scripts /usr/share/openvswitch/scripts
COPY --from=ovn /out/ovn /
