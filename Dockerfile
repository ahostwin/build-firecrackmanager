# syntax=docker/dockerfile:1

FROM --platform=linux/amd64 golang:1.24-bookworm AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    build-essential \
    libsqlite3-dev \
  && rm -rf /var/lib/apt/lists/*

ARG REPO_URL=https://github.com/ahostwin/firecrackmanager.git
ARG GIT_DEPTH=100

# Passed by Makefile from `git ls-remote … HEAD`; when it changes, this layer rebuilds while base image layers stay cached.
ARG SOURCE_REV

WORKDIR /src

RUN set -eux; \
    if [ -z "${SOURCE_REV}" ]; then echo "Dockerfile: SOURCE_REV build-arg is required (Makefile sets it via git ls-remote)" >&2; exit 1; fi; \
    rm -rf /src/* /src/.[!.]* /src/..?* 2>/dev/null || true; \
    git init /src; \
    cd /src; \
    git remote add origin "${REPO_URL}"; \
    if [ "${GIT_DEPTH}" = "0" ]; then \
      git fetch origin "${SOURCE_REV}"; \
    else \
      git fetch --depth "${GIT_DEPTH}" origin "${SOURCE_REV}"; \
    fi; \
    git checkout -q "${SOURCE_REV}"

RUN mkdir -p /build \
  && cd /src \
  && desc="$(git describe --tags --always 2>/dev/null || true)" \
  && sha="$(git rev-parse --short HEAD)" \
  && tag_part="${desc%%-[0-9]*-g*}" \
  && if [ -n "${desc}" ] && [ "${desc}" != "${sha}" ]; then \
       case "${tag_part}" in \
         *+*) base="${tag_part%%+*}"; ver="${base}+${sha}" ;; \
         *)   ver="${desc}" ;; \
       esac; \
     else \
       ver="0.0.0+${sha}"; \
     fi \
  && printf '%s' "${ver}" > /build/VERSION

ENV CGO_ENABLED=1

RUN cd /src && go build -trimpath -ldflags='-s -w' -o /build/firecrackmanager ./cmd/firecrackmanager

FROM --platform=linux/amd64 debian:bookworm-slim AS packager

RUN apt-get update && apt-get install -y --no-install-recommends \
    dpkg-dev \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/firecrackmanager /tmp/firecrackmanager
COPY --from=builder /build/VERSION /tmp/VERSION
COPY --from=builder /src/scripts/firecrackmanager.service /tmp/firecrackmanager.service

RUN set -eux; \
    VERSION_RAW="$(tr -d '\n\r' < /tmp/VERSION)"; \
    VERSION="$(printf '%s' "${VERSION_RAW}" | sed 's/[\/[:space:]]/-/g' | sed -E 's/^([0-9a-f]{7,40})$/0.0.0+\1/')"; \
    ARCH=amd64; \
    STAGE=/tmp/stage; \
    rm -rf "${STAGE}"; \
    mkdir -p "${STAGE}/DEBIAN" "${STAGE}/usr/local/bin" "${STAGE}/etc/firecrackmanager" "${STAGE}/etc/systemd/system"; \
    install -m 0755 /tmp/firecrackmanager "${STAGE}/usr/local/bin/firecrackmanager"; \
    install -m 0644 /tmp/firecrackmanager.service "${STAGE}/etc/systemd/system/firecrackmanager.service"; \
    touch "${STAGE}/etc/firecrackmanager/.gitkeep"; \
    chmod 0644 "${STAGE}/etc/firecrackmanager/.gitkeep"; \
    { \
      echo "Package: firecrackmanager"; \
      echo "Version: ${VERSION}"; \
      echo "Section: admin"; \
      echo "Priority: optional"; \
      echo "Architecture: amd64"; \
      echo "Maintainer: Local Build <local@localhost>"; \
      echo "Depends: libc6, libsqlite3-0, iptables, openssl"; \
      echo "Description: FireCrackManager - MicroVM management daemon"; \
    } > "${STAGE}/DEBIAN/control"; \
    printf '%s\n' '#!/bin/sh' 'set -e' 'if [ -d /run/systemd/system ]; then systemctl daemon-reload 2>/dev/null || true; fi' 'exit 0' > "${STAGE}/DEBIAN/postinst"; \
    chmod 0755 "${STAGE}/DEBIAN/postinst"; \
    mkdir -p /artifacts; \
    DEB_NAME="firecrackmanager_${VERSION}_${ARCH}.deb"; \
    dpkg-deb --build --root-owner-group "${STAGE}" "/artifacts/${DEB_NAME}"; \
    cp /tmp/firecrackmanager "/artifacts/firecrackmanager"; \
    cd /artifacts && sha256sum firecrackmanager "${DEB_NAME}" > SHA256SUMS

FROM --platform=linux/amd64 debian:bookworm-slim AS export

COPY --from=packager /artifacts /artifacts

CMD ["sh", "-c", "mkdir -p /dist && cp -a /artifacts/. /dist/"]
