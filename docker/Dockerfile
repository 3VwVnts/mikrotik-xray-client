# =========================================================
# Stage 1: fetch static binaries
# =========================================================
FROM alpine:3.21 AS fetch

ARG TARGETARCH
ARG TARGETVARIANT
ARG XRAY_VERSION=v25.9.11
ARG TUN2SOCKS_VERSION=v2.5.2
ARG GEODATA_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download"

RUN apk add --no-cache curl unzip ca-certificates

WORKDIR /tmp

# --- Xray-core (official static binary) ---
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
    unzip xray.zip xray; chmod +x xray

# --- tun2socks (xjasonlyu, static Go) ---
RUN set -e; \
    case "${TARGETARCH}${TARGETVARIANT}" in \
      amd64)  T2S_ARCH="amd64" ;; \
      arm64)  T2S_ARCH="arm64" ;; \
      armv7)  T2S_ARCH="armv7" ;; \
      armv6)  T2S_ARCH="armv6" ;; \
      *) echo "Unsupported arch: ${TARGETARCH}${TARGETVARIANT}"; exit 1 ;; \
    esac; \
    echo "Fetching tun2socks ${TUN2SOCKS_VERSION} (${T2S_ARCH})"; \
    curl -fL -o tun2socks.gz \
      "https://github.com/xjasonlyu/tun2socks/releases/download/${TUN2SOCKS_VERSION}/tun2socks-linux-${T2S_ARCH}.gz"; \
    gunzip tun2socks.gz; chmod +x tun2socks

# --- GeoIP / GeoSite (baked-in fallback) ---
RUN curl -fL -o geoip.dat   "${GEODATA_URL}/geoip.dat" && \
    curl -fL -o geosite.dat "${GEODATA_URL}/geosite.dat"

# =========================================================
# Stage 2: final image
# =========================================================
FROM alpine:3.21

RUN apk add --no-cache \
      ca-certificates \
      iproute2 \
      jq \
      tzdata \
      curl

COPY --from=fetch /tmp/xray        /usr/local/bin/xray
COPY --from=fetch /tmp/tun2socks   /usr/local/bin/tun2socks

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
