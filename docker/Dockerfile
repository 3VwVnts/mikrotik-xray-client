# syntax=docker/dockerfile:1

# =========================================================
# Stage 1: hev-socks5-tunnel
# =========================================================
FROM alpine:3.21 AS hev

ARG HEV_VERSION="2.17.1"

RUN apk add --no-cache \
    git make gcc musl-dev linux-headers

WORKDIR /src

RUN git clone --depth 1 --branch "${HEV_VERSION}" --recursive \
        https://github.com/heiher/hev-socks5-tunnel . \
    && make ENABLE_STATIC=1 \
    && strip bin/hev-socks5-tunnel

# =========================================================
# Stage 2: Xray-core + geo data
# =========================================================
FROM alpine:3.21 AS fetch

ARG TARGETARCH
ARG TARGETVARIANT
ARG XRAY_VERSION=v26.3.27
ARG GEODATA_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download"

RUN apk add --no-cache curl unzip ca-certificates

WORKDIR /tmp

RUN set -e; \
    case "${TARGETARCH}${TARGETVARIANT}" in \
      amd64)  XRAY_ARCH="64" ;; \
      arm64)  XRAY_ARCH="arm64-v8a" ;; \
      armv7)  XRAY_ARCH="arm32-v7a" ;; \
      armv6)  XRAY_ARCH="arm32-v6" ;; \
      *) echo "Unsupported arch: ${TARGETARCH}${TARGETVARIANT}"; exit 1 ;; \
    esac; \
    echo "Fetching Xray ${XRAY_VERSION} (${XRAY_ARCH})"; \
    curl -fL -o xray.zip \
      "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-${XRAY_ARCH}.zip"; \
    unzip -o xray.zip xray; chmod +x xray

RUN curl -fL -o geoip.dat   "${GEODATA_URL}/geoip.dat" && \
    curl -fL -o geosite.dat "${GEODATA_URL}/geosite.dat"

# =========================================================
# Stage 3: final image
# =========================================================
FROM alpine:3.21

RUN apk add --no-cache \
    ca-certificates \
    iproute2 \
    jq \
    tzdata \
    curl

COPY --from=hev   /src/bin/hev-socks5-tunnel /usr/local/bin/hev-socks5-tunnel
COPY --from=fetch /tmp/xray                  /usr/local/bin/xray

RUN mkdir -p /usr/local/share/xray
COPY --from=fetch /tmp/geoip.dat   /usr/local/share/xray/geoip.dat
COPY --from=fetch /tmp/geosite.dat /usr/local/share/xray/geosite.dat

RUN mkdir -p /var/lib/xray/geo

COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV XRAY_LOCATION_CONFIG=/etc/xray/config.json \
    GEO_CACHE_DIR=/var/lib/xray/geo \
    GEO_MAX_AGE_DAYS=3

VOLUME ["/var/lib/xray/geo"]

ENTRYPOINT ["/entrypoint.sh"]
