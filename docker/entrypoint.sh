#!/bin/sh
set -e

# ============================================================
# ENV
# ============================================================
VLESS_URI="${VLESS_URI:-}"
PROXY_MODE="${PROXY_MODE:-hev-tunnel}"
LOG_LEVEL="${LOG_LEVEL:-info}"
TUN_DEV="${TUN_DEV:-tun0}"
TUN_IPV4="${TUN_IPV4:-198.18.0.1}"
TUN_IPV6="${TUN_IPV6:-fc00::1}"
TUN_MTU="${TUN_MTU:-8500}"
SOCKS_PORT="${SOCKS_PORT:-10808}"
HTTP_PORT="${HTTP_PORT:-10809}"
CUSTOM_RULES_FILE="${CUSTOM_RULES_FILE:-/etc/xray/custom-rules.json}"
CONFIG_FILE="${XRAY_LOCATION_CONFIG:-/etc/xray/config.json}"
HEV_CONFIG="/etc/xray/hev-tunnel.yml"
GEO_CACHE_DIR="${GEO_CACHE_DIR:-/var/lib/xray/geo}"
GEO_MAX_AGE_DAYS="${GEO_MAX_AGE_DAYS:-3}"
GEO_FORCE_UPDATE="${GEO_FORCE_UPDATE:-0}"
GEO_SKIP_DOWNLOAD="${GEO_SKIP_DOWNLOAD:-0}"
DEBUG_HOLD="${DEBUG_HOLD:-0}"
GEODATA_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download"
XRAY_MARK=255
TUN_TABLE=20

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
# Generate Xray config.json
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
        sockopt: { mark: $mark },
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

log "Xray config written: $CONFIG_FILE"
xray run -test -c "$CONFIG_FILE" || die "Xray config test failed"
log "Xray config test OK"

# ============================================================
# SOCKS-only mode
# ============================================================
if [ "$PROXY_MODE" = "socks-only" ]; then
  log "Starting Xray in SOCKS-only mode (127.0.0.1:$SOCKS_PORT)"
  exec xray run -c "$CONFIG_FILE"
fi

# ============================================================
# hev-socks5-tunnel mode
# ============================================================
log "=== hev-socks5-tunnel mode ==="

sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null 2>&1 || true
sysctl -w net.ipv4.conf.default.rp_filter=0 >/dev/null 2>&1 || true

# --- Удаляем stale tun0 (если остался от прошлого запуска) ---
if ip link show "$TUN_DEV" >/dev/null 2>&1; then
  log "Removing stale $TUN_DEV"
  ip link delete "$TUN_DEV" 2>/dev/null || true
  sleep 1
fi

# --- Проверка бинарника hev ---
log "Checking hev-socks5-tunnel binary"
ls -la /usr/local/bin/hev-socks5-tunnel || die "hev-socks5-tunnel not found"
/usr/local/bin/hev-socks5-tunnel --help 2>&1 | head -5 || log "  --help exit: $?"

# --- Минимальный конфиг hev (как в рабочем byedpi) ---
mkdir -p "$(dirname "$HEV_CONFIG")"
cat > "$HEV_CONFIG" <<EOF
tunnel:
  name: ${TUN_DEV}
  mtu: ${TUN_MTU}
  multi-queue: false
  ipv4: ${TUN_IPV4}
  ipv6: '${TUN_IPV6}'
  icmp: 'off'

socks5:
  port: ${SOCKS_PORT}
  address: 127.0.0.1
  udp: 'udp'

misc:
  log-level: ${LOG_LEVEL}
EOF

log "hev-tunnel config:"
cat "$HEV_CONFIG"

# --- 1. Xray ---
log "Starting Xray"
xray run -c "$CONFIG_FILE" &
XRAY_PID=$!
sleep 2
kill -0 "$XRAY_PID" 2>/dev/null || die "Xray died on start"
log "Xray started (PID=$XRAY_PID)"

# --- 2. hev-socks5-tunnel ---
HEV_LOG=/tmp/hev-tunnel.log
log "Starting hev-socks5-tunnel → socks5://127.0.0.1:$SOCKS_PORT"
/usr/local/bin/hev-socks5-tunnel "$HEV_CONFIG" > "$HEV_LOG" 2>&1 &
HEV_PID=$!
log "hev-socks5-tunnel launched, PID=$HEV_PID"

# Даём 2 секунды и смотрим, что он жив и что пишет в лог
sleep 2
if kill -0 "$HEV_PID" 2>/dev/null; then
  log "hev PID=$HEV_PID: ALIVE"
  log "hev log (first 20 lines):"
  head -20 "$HEV_LOG" 2>&1 || log "  (log empty or unreadable)"
else
  EXIT_CODE=$(wait "$HEV_PID" 2>/dev/null; echo $?)
  log "hev PID=$HEV_PID: DEAD (exit=$EXIT_CODE)"
  log "hev log content:"
  cat "$HEV_LOG" 2>&1 || log "  (log empty or unreadable)"
  if [ "$DEBUG_HOLD" = "1" ]; then
    log "DEBUG_HOLD=1: sleeping 600s"
    sleep 600
  fi
  die "hev-socks5-tunnel died"
fi

# --- 3. Ждём tun0 ---
TUN_WAIT=0
TUN_MAX_WAIT=15
while [ "$TUN_WAIT" -lt "$TUN_MAX_WAIT" ]; do
  if ip link show "$TUN_DEV" 2>/dev/null | grep -q "state UP"; then
    log "$TUN_DEV is UP (after ${TUN_WAIT}s)"
    break
  fi
  if ! kill -0 "$HEV_PID" 2>/dev/null; then
    EXIT_CODE=$(wait "$HEV_PID" 2>/dev/null; echo $?)
    log "[ERROR] hev died during wait (exit=$EXIT_CODE)"
    log "[ERROR] hev log:"
    cat "$HEV_LOG" 2>&1 || true
    if [ "$DEBUG_HOLD" = "1" ]; then
      log "DEBUG_HOLD=1: sleeping 600s"
      sleep 600
    fi
    die "hev-socks5-tunnel died"
  fi
  sleep 1
  TUN_WAIT=$((TUN_WAIT + 1))
done

if ! ip link show "$TUN_DEV" 2>/dev/null | grep -q "state UP"; then
  log "[ERROR] $TUN_DEV did not come up within ${TUN_MAX_WAIT}s"
  log "[ERROR] hev PID=$HEV_PID still alive? $(kill -0 $HEV_PID 2>/dev/null && echo yes || echo no)"
  log "[ERROR] Interface list:"
  ip -br link show
  log "[ERROR] hev log content:"
  cat "$HEV_LOG" 2>&1 || true
  if [ "$DEBUG_HOLD" = "1" ]; then
    log "DEBUG_HOLD=1: sleeping 600s"
    sleep 600
  fi
  die "$TUN_DEV failed to come up"
fi

log "hev-socks5-tunnel running (PID=$HEV_PID)"

# --- 4. Policy routing ---
log "Configuring policy routing"
ip rule del fwmark "$XRAY_MARK" lookup main pref 10 2>/dev/null || true
ip rule del lookup "$TUN_TABLE" pref 20 2>/dev/null || true
ip route flush table "$TUN_TABLE" 2>/dev/null || true

ip rule add fwmark "$XRAY_MARK" lookup main pref 10
ip route add default dev "$TUN_DEV" table "$TUN_TABLE"
ip rule add lookup "$TUN_TABLE" pref 20

log "Policy routing configured"

# --- 5. Отчёт ---
log "=== Routes (main) ==="
ip route show
log "=== Routes (table $TUN_TABLE) ==="
ip route show table "$TUN_TABLE"
log "=== Rules ==="
ip rule show
log "=== Interfaces ==="
ip -br link show
log "=== hev-tunnel log tail ==="
tail -30 "$HEV_LOG" 2>/dev/null || true

trap 'log "Stopping..."; kill $HEV_PID $XRAY_PID 2>/dev/null; wait; exit 0' TERM INT
wait $XRAY_PID $HEV_PID
