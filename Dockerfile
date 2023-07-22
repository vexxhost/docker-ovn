# syntax=docker/dockerfile:1.4

ARG FROM
FROM ${FROM}

FROM ${FROM} AS repository-generator
RUN <<EOF
  set -xe
  apt-get update
  apt-get install -y lsb-release
  apt-get clean
  rm -rf /var/lib/apt/lists/*
EOF
ARG RELEASE
RUN <<EOF /bin/bash
  set -xe
  if [ "$(lsb_release -sc)" = "focal" ]; then
    if [[ "${RELEASE}" = "wallaby" || "${RELEASE}" = "xena" || "${RELEASE}" = "yoga" ]]; then
      echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu $(lsb_release -sc)-updates/${RELEASE} main" > /etc/apt/sources.list.d/cloudarchive.list
    else
      echo "${RELEASE} is not supported on $(lsb_release -sc)"
      exit 1
    fi
  elif [ "$(lsb_release -sc)" = "jammy" ]; then
    if [[ "${RELEASE}" = "yoga" ]]; then
      # NOTE(mnaser): Yoga shipped with 22.04, so no need to add an extra repository.
      echo "" > /etc/apt/sources.list.d/cloudarchive.list
    elif [[ "${RELEASE}" = "zed" || "${RELEASE}" = "antelope" ]]; then
      echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu $(lsb_release -sc)-updates/${RELEASE} main" > /etc/apt/sources.list.d/cloudarchive.list
    else
      echo "${RELEASE} is not supported on $(lsb_release -sc)"
      exit 1
    fi
  else
    echo "Unable to detect correct Ubuntu Cloud Archive repository for $(lsb_release -sc)"
    exit 1
  fi
EOF


FROM ${FROM} AS ovn
COPY --from=repository-generator --link /etc/apt/sources.list.d/cloudarchive.list /etc/apt/sources.list.d/cloudarchive.list
COPY ubuntu-keyring-2012-cloud-archive.gpg /etc/apt/trusted.gpg.d/ubuntu-keyring-2012-cloud-archive.gpg
RUN \
  apt-get update && \
  apt-get install -y --no-install-recommends ovn-common && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

FROM ovn AS ovn-central
RUN \
  apt-get update && \
  apt-get install -y --no-install-recommends ovn-central && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

FROM ovn AS ovn-host
ARG VERSION=23.03.0
RUN \
  apt-get update && \
  apt-get install -y --no-install-recommends ovn-host iproute2 && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*
