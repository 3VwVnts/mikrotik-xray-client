#!/bin/sh
set -e

# ============================================================
# ENV
# ============================================================
VLESS_URI="${VLESS_URI:-}"
PROXY_MODE="${PROXY_MODE:-tun2socks}"
LOG_LEVEL="${LOG_LEVEL:-warning}"
TUN_DEV="${TUN_DEV:-tun0}"
TUN_ADDR="${TUN_ADDR:-198.18.0.1/15}"
SOCKS_PORT="${SOCKS_PORT:-10808}"
HTTP_PORT="${HTTP_PORT:-10809}"
CUSTOM_RULES_FILE="${CUSTOM_RULES_FILE:-/etc/xray/custom-rules.json}"
CONFIG_FILE="${XRAY_LOCATION_CONFIG:-/etc/xray/config.json}"
GEO_CACHE_DIR="${GEO_CACHE_DIR:-/var/lib/xray/geo}"
GEO_MAX_AGE_DAYS="${GEO_MAX_AGE_DAYS:-3}"
GEO_FORCE_UPDATE="${GEO_FORCE_UPDATE:-0}"
GEO_SKIP_DOWNLOAD="${GEO_SKIP_DOWNLOAD:-0}"
GEODATA_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download"
XRAY_MARK=255

log() { echo "[entrypoint] $*"; }
die() { echo "[entrypoint][ERROR] $*" >&2; exit 1; }

[ -n "$VLESS_URI" ] || die "VLESS_URI env is required"

# ============================================================
# Geo data management
# ============================================================
ensure_geo_data() {
  mkdir -p "$GEO_CACHE_DIR"

  if [ "$GEO_SKIP_DOWNLOAD" = "1" ]; then
    log "Geo: download disabled, seeding from baked-in"
    [ -f "$GEO_CACHE_DIR/geoip.dat" ]   || cp /usr/local/share/xray/geoip.dat   "$GEO_CACHE_DIR/geoip.dat"
    [ -f "$GEO_CACHE_DIR/geosite.dat" ] || cp /usr/local/share/xray/geosite.dat "$GEO_CACHE_DIR/geosite.dat"
    return 0
  fi

  local need_update=0

  for f in geoip.dat geosite.dat; do
    local path="$GEO_CACHE_DIR/$f"
    if [ ! -f "$path" ]; then
      log "Geo: $f missing, will download"
      need_update=1
      continue
    fi
    local age_sec age_days
    age_sec=$(( $(date +%s) - $(date -r "$path" +%s) ))
    age_days=$(( age_sec / 86400 ))
    log "Geo: $f age=${age_days}d"
    if [ "$GEO_FORCE_UPDATE" = "1" ]; then
      need_update=1
    elif [ "$age_days" -ge "$GEO_MAX_AGE_DAYS" ]; then
      need_update=1
    fi
  done

  if [ "$need_update" = "0" ]; then
    log "Geo: cache is fresh"
    return 0
  fi

  log "Geo: updating from Loyalsoldier..."
  local tmp_dl="/tmp/geodl.$$"
  mkdir -p "$tmp_dl"

  local ok=1
  for f in geoip.dat geosite.dat; do
    if curl -fsSL --max-time 60 -o "$tmp_dl/$f" "$GEODATA_URL/$f"; then
      log "Geo: downloaded $f ($(wc -c < "$tmp_dl/$f") bytes)"
    else
      log "Geo: failed to download $f"
      ok=0
      break
    fi
  done

  if [ "$ok" = "1" ]; then
    mv "$tmp_dl/geoip.dat"   "$GEO_CACHE_DIR/geoip.dat"
    mv "$tmp_dl/geosite.dat" "$GEO_CACHE_DIR/geosite.dat"
    log "Geo: cache updated"
  else
    log "Geo: falling back to baked-in"
    [ -f "$GEO_CACHE_DIR/geoip.dat" ]   || cp /usr/local/share/xray/geoip.dat   "$GEO_CACHE_DIR/geoip.dat"
    [ -f "$GEO_CACHE_DIR/geosite.dat" ] || cp /usr/local/share/xray/geosite.dat "$GEO_CACHE_DIR/geosite.dat"
  fi

  rm -rf "$tmp_dl"
}

ensure_geo_data
export XRAY_LOCATION_ASSET="$GEO_CACHE_DIR"

# ============================================================
# Parse VLESS URI
# ============================================================
parse_vless_uri() {
  local uri="$1"
  local scheme rest userinfo hostpart query

  scheme="${uri%%://*}"
  rest="${uri#*://}"
  userinfo="${rest%%@*}"
  rest="${rest#*@}"
  hostpart="${rest%%\?*}"
  query="${rest#*\?}"
  query="${query%%#*}"

  UUID="$userinfo"
  SERVER="${hostpart%%:*}"
  PORT="${hostpart##*:}"

  OLD_IFS="$IFS"; IFS='&'
  for pair in $query; do
    key="${pair%%=*}"; val="${pair#*=}"
    case "$key" in
      type)       TYPE="$val" ;;
      security)   SECURITY="$val" ;;
      pbk)        PBK="$val" ;;
      sid)        SID="$val" ;;
      sni)        SNI="$val" ;;
      fp)         FP="$val" ;;
      flow)       FLOW="$val" ;;
      encryption) ENCRYPTION="$val" ;;
    esac
  done
  IFS="$OLD_IFS"

  PROTOCOL="$scheme"
  : "${TYPE:=tcp}"
  : "${SECURITY:=reality}"
  : "${FP:=chrome}"
  : "${ENCRYPTION:=none}"
  : "${FLOW:=xtls-rprx-vision}"
}

parse_vless_uri "$VLESS_URI"
[ -n "$SERVER" ] || die "Failed to parse server from URI"
[ -n "$UUID" ]   || die "Failed to parse UUID from URI"
[ -n "$PORT" ]   || die "Failed to parse port from URI"

log "Parsed: proto=$PROTOCOL server=$SERVER:$PORT sni=$SNI fp=$FP flow=$FLOW"

# ============================================================
# Routing rules
# ============================================================
BASE_RULES='[
  {"type":"field","outboundTag":"block","domain":["geosite:category-ads-all"]},
  {"type":"field","outboundTag":"direct","domain":["geosite:category-ru","geosite:private"]},
  {"type":"field","outboundTag":"proxy","domain":["geosite:youtube","geosite:google","geosite:meta","geosite:openai","geosite:twitter","geosite:telegram","geosite:cloudflare"]},
  {"type":"field","outboundTag":"proxy","port":53}
]'

CUSTOM_RULES='[]'
if [ -f "$CUSTOM_RULES_FILE" ]; then
  log "Loading custom rules: $CUSTOM_RULES_FILE"
  PD=$(jq -c '.proxy_domains  // []' "$CUSTOM_RULES_FILE")
  PI=$(jq -c '.proxy_ips      // []' "$CUSTOM_RULES_FILE")
  DD=$(jq -c '.direct_domains // []' "$CUSTOM_RULES_FILE")
  DI=$(jq -c '.direct_ips     // []' "$CUSTOM_RULES_FILE")

  CUSTOM_RULES=$(jq -n \
    --argjson pd "$PD" --argjson pi "$PI" \
    --argjson dd "$DD" --argjson di "$DI" '
    [
      (if ($pd|length) > 0 then {type:"field",outboundTag:"proxy", domain:$pd}  else empty end),
      (if ($pi|length) > 0 then {type:"field",outboundTag:"proxy", ip:$pi}      else empty end),
      (if ($dd|length) > 0 then {type:"field",outboundTag:"direct",domain:$dd}  else empty end),
      (if ($di|length) > 0 then {type:"field",outboundTag:"direct",ip:$di}      else empty end)
    ]')
fi

FINAL_RULES='[
  {"type":"field","outboundTag":"direct","ip":["geoip:private","geoip:ru"]},
  {"type":"field","outboundTag":"direct","network":"tcp,udp"}
]'

ALL_RULES=$(jq -n \
  --argjson b "$BASE_RULES" \
  --argjson c "$CUSTOM_RULES" \
  --argjson f "$FINAL_RULES" '$b + $c + $f')

# ============================================================
# Generate config.json
# ============================================================
mkdir -p "$(dirname "$CONFIG_FILE")"

jq -n \
  --arg     uuid       "$UUID" \
  --arg     server     "$SERVER" \
  --argjson port       "$PORT" \
  --arg     sni        "$SNI" \
  --arg     pbk        "$PBK" \
  --arg     sid        "$SID" \
  --arg     fp         "$FP" \
  --arg     flow       "$FLOW" \
  --argjson socks_port "$SOCKS_PORT" \
  --argjson http_port  "$HTTP_PORT" \
  --argjson rules      "$ALL_RULES" \
  --argjson mark       "$XRAY_MARK" '
{
  log: { loglevel: "warning", access: "none" },
  inbounds: [
    {
      tag: "socks-in", listen: "127.0.0.1", port: $socks_port,
      protocol: "socks",
      settings: { auth: "noauth", udp: true },
      sniffing: { enabled: true, destOverride: ["http","tls","quic"], routeOnly: false }
    },
    {
      tag: "http-in", listen: "127.0.0.1", port: $http_port,
      protocol: "http",
      sniffing: { enabled: true, destOverride: ["http","tls"] }
    }
  ],
  outbounds: [
    {
      tag: "proxy", protocol: "vless",
      settings: { vnext: [{ address: $server, port: $port,
        users: [{ id: $uuid, encryption: "none", flow: $flow }] }] },
      streamSettings: {
        network: "tcp",
        security: "reality",
        realitySettings: {
          serverName: $sni, fingerprint: $fp,
          publicKey: $pbk, shortId: $sid, spiderX: "/"
        }
      }
    },
    {
      tag: "direct", protocol: "freedom",
      settings: { domainStrategy: "UseIPv4" },
      streamSettings: { sockopt: { mark: $mark } }
    },
    { tag: "block", protocol: "blackhole" }
  ],
  routing: { domainStrategy: "IPIfNonMatch", rules: $rules },
  dns: {
    servers: [
      { address: "1.1.1.1",  domains: ["geosite:geolocation-!cn"] },
      { address: "77.88.8.8", domains: ["geosite:category-ru"], expectIPs: ["geoip:ru"] },
      "localhost"
    ]
  }
}' > "$CONFIG_FILE"

log "Config written: $CONFIG_FILE"
xray run -test -c "$CONFIG_FILE" || die "Xray config test failed"
log "Config test OK"

# ============================================================
# SOCKS-only mode
# ============================================================
if [ "$PROXY_MODE" = "socks-only" ]; then
  log "Starting Xray in SOCKS-only mode (127.0.0.1:$SOCKS_PORT)"
  exec xray run -c "$CONFIG_FILE"
fi

# ============================================================
# tun2socks mode
# ============================================================
log "Setting up TUN $TUN_DEV"
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null 2>&1 || true
sysctl -w net.ipv4.conf.default.rp_filter=0 >/dev/null 2>&1 || true

log "Normalizing ip rule priorities (RouterOS 7.22+ fix)"
while ip rule show | grep -Eq '^1:\s+from all lookup local'; do
  ip rule del pref 1 2>/dev/null || break
done
while ip rule show | grep -Eq '^2:\s+from all lookup main'; do
  ip rule del pref 2 2>/dev/null || break
done
while ip rule show | grep -Eq '^3:\s+from all lookup default'; do
  ip rule del pref 3 2>/dev/null || break
done
ip rule add pref 200 from all lookup local 2>/dev/null || true
ip rule add pref 2147483646 from all lookup main 2>/dev/null || true
ip rule add pref 2147483647 from all lookup default 2>/dev/null || true

# --- Автодетект внешнего интерфейса ---
ETH_DEV=$(ip -o -4 addr show | awk '$4 ~ /^172\.17\./ {print $2; exit}' | sed 's/@.*//')
if [ -z "$ETH_DEV" ]; then
  ETH_DEV=$(ip -o link show | awk -F': ' '$2!="lo" && $2!~/^tun/ {print $2; exit}' | sed 's/@.*//')
fi
[ -n "$ETH_DEV" ] || die "Cannot detect external interface"
log "External interface: $ETH_DEV"

# --- Получаем IP и шлюз с этого интерфейса ---
VETH_IP=$(ip -o -4 addr show dev "$ETH_DEV" | awk '{print $4}' | cut -d/ -f1)
log "Container IP: $VETH_IP"

HOST_GW=$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}')
[ -n "$HOST_GW" ] || die "Cannot detect host gateway"
log "Host gateway: $HOST_GW"

# --- Резолвим VPS IP ---
VPS_IP=$(getent ahostsv4 "$SERVER" 2>/dev/null | awk 'NR==1{print $1}')
[ -n "$VPS_IP" ] || VPS_IP="$SERVER"
log "VPS IP: $VPS_IP"

# --- Policy routing: fwmark 255 → table 100 ---
log "Configuring policy routing (fwmark=$XRAY_MARK → table 100)"

# Правило fwmark
ip rule del fwmark "$XRAY_MARK" lookup 100 2>/dev/null || true
ip rule add fwmark "$XRAY_MARK" lookup 100 priority 100

ip route replace 172.17.0.0/24 dev "$ETH_DEV" scope link table 100
log "  table 100: 172.17.0.0/24 dev $ETH_DEV scope link"

# Теперь default через шлюз
ip route replace default via "$HOST_GW" dev "$ETH_DEV" onlink table 100
log "  table 100: default via $HOST_GW dev $ETH_DEV"

# --- Фиксируем маршруты до VPS и LAN в main ---
log "Pinning routes to VPS and LAN in main table"
ip route replace "$VPS_IP" via "$HOST_GW" dev "$ETH_DEV" 2>/dev/null || true
ip route replace 192.168.10.0/24 via "$HOST_GW" dev "$ETH_DEV" 2>/dev/null || true
ip route replace 10.10.10.0/24 via "$HOST_GW" dev "$ETH_DEV" 2>/dev/null || true

# --- Запускаем Xray ---
log "Starting Xray"
xray run -c "$CONFIG_FILE" &
XRAY_PID=$!
sleep 2
kill -0 "$XRAY_PID" 2>/dev/null || die "Xray process died"
log "Xray started (PID=$XRAY_PID)"

# --- ДИАГНОСТИКА tun2socks ---
log "=== tun2socks binary diagnostics ==="
if [ -f /usr/local/bin/tun2socks ]; then
  log "  file exists"
  ls -la /usr/local/bin/tun2socks 2>&1 || true
  if [ -x /usr/local/bin/tun2socks ]; then
    log "  executable: YES"
  else
    log "  executable: NO — chmod +x"
  fi
else
  log "  file MISSING at /usr/local/bin/tun2socks"
fi

log "=== tun2socks --version ==="
/usr/local/bin/tun2socks --version 2>&1 || log "  --version exit code: $?"

log "=== tun2socks --help (first 30 lines) ==="
/usr/local/bin/tun2socks --help 2>&1 | head -30 || log "  --help exit code: $?"

log "=== /dev/net/tun ==="
ls -la /dev/net/ 2>&1 || log "  /dev/net missing"

log "=== End diagnostics ==="

# --- Запускаем tun2socks ---
T2S_LOG=/tmp/tun2socks.log
log "Starting tun2socks → socks5://127.0.0.1:$SOCKS_PORT"
tun2socks \
  -device "tun://$TUN_DEV" \
  -proxy  "socks5://127.0.0.1:$SOCKS_PORT" \
  -tcp-sniff -udp-sniff \
  -loglevel debug \
  > "$T2S_LOG" 2>&1 &
T2S_PID=$!

sleep 3
if ! kill -0 "$T2S_PID" 2>/dev/null; then
  EXIT_CODE=$(wait "$T2S_PID" 2>/dev/null; echo $?)
  log "[ERROR] tun2socks died. Exit code: $EXIT_CODE"
  log "[ERROR] Log file size: $(wc -c < "$T2S_LOG" 2>/dev/null || echo unknown) bytes"
  log "[ERROR] Log content:"
  cat "$T2S_LOG" 2>&1 || log "  (cannot read log)"
  log "[ERROR] End of tun2socks log"

  if [ "${DEBUG_HOLD:-0}" = "1" ]; then
    log "DEBUG_HOLD=1: container will sleep 600s for manual inspection"
    log "  Connect via: /container/shell xray-client"
    sleep 600
  fi

  die "tun2socks died immediately after start"
fi
log "tun2socks started (PID=$T2S_PID)"

# --- Меняем default route на tun0 ---
ip route replace default dev "$TUN_DEV"
log "Default route → $TUN_DEV"

log "=== Routes ==="
ip route show
log "=== Rules ==="
ip rule show
log "=== Interfaces ==="
ip -br link show

# --- Signal handling ---
trap 'log "Stopping..."; kill $T2S_PID $XRAY_PID 2>/dev/null; wait; exit 0' TERM INT
wait $XRAY_PID $T2S_PID
