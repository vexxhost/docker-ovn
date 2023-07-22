ARG FROM=fedora:38

FROM ${FROM} AS ovn
ARG VERSION=23.06.0
RUN \
  dnf install -y ovn-${VERSION} && \
  dnf clean all && \
  rm -rf /var/cache/dnf

FROM ${FROM} AS ovn-central
ARG VERSION=23.06.0
RUN \
  dnf install -y ovn-central-${VERSION} && \
  dnf clean all && \
  rm -rf /var/cache/dnf

FROM ${FROM} AS ovn-host
ARG VERSION=23.06.0
RUN \
  dnf install -y ovn-host-${VERSION} && \
  dnf clean all && \
  rm -rf /var/cache/dnf
