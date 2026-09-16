# ============================================================
# 02-container.rsc
# Контейнер Xray + hev-socks5-tunnel.
# USER CONFIG — единственное место, где нужны правки
# ============================================================
:local vlessURI "PLACEHOLDER_VLESS_URI"
:local imageName "ghcr.io/3vwvnts/mikrotik-xray-gateway:latest"
:local containerName "xray-gateway"
:local vethName "veth-xray"
# ============================================================

:log info "02: starting container setup"

# --- 0. Проверка VLESS_URI ---
:if ($vlessURI = "PLACEHOLDER_VLESS_URI") do={
    :log error "02: VLESS_URI not set. Edit the USER CONFIG block"
    :error "VLESS_URI placeholder not replaced"
}

# --- 1. Проверка veth ---
:if ([:len [/interface veth find where name=$vethName]] = 0) do={
    :log error "02: $vethName not found. Run 01-bridge-veth.rsc first."
    :error "veth missing"
}

# --- 2. Миграция: удаляем контейнер старого имени ---
:if ([:len [/container find where name="xray-client"]] > 0) do={
    :do { /container/stop [find name="xray-client"] } on-error={}
    :delay 3s
    /container/remove [find name="xray-client"]
    :log info "02: removed legacy container xray-client"
}

# --- 3. Удаляем устаревший geo-mount (выпилен из образа) ---
:if ([:len [/container/mounts find where list="geo"]] > 0) do={
    /container/mounts remove [find list="geo"]
    :log info "02: removed obsolete geo mount"
}

# --- 4. Mount custom-rules.json ---
:if ([:len [/container/mounts find where list="custom-rules"]] = 0) do={
    /container/mounts add list=custom-rules src=custom-rules.json dst=/etc/xray/custom-rules.json
    :log info "02: added custom-rules mount"
}

# --- 5. ENV: VLESS_URI ---
:if ([:len [/container/envs find where list="xray-envs" and key="VLESS_URI"]] = 0) do={
    /container/envs add list=xray-envs key=VLESS_URI value=$vlessURI
} else={
    /container/envs set [find list="xray-envs" key="VLESS_URI"] value=$vlessURI
}

# --- 6. ENV: остальные (v3, без GEO-переменных) ---
:if ([:len [/container/envs find where list="xray-envs" and key="PROXY_MODE"]] = 0) do={
    /container/envs add list=xray-envs key=PROXY_MODE value="hev-tunnel"
} else={ /container/envs set [find list="xray-envs" key="PROXY_MODE"] value="hev-tunnel" }

:if ([:len [/container/envs find where list="xray-envs" and key="LOG_LEVEL"]] = 0) do={
    /container/envs add list=xray-envs key=LOG_LEVEL value="warn"
} else={ /container/envs set [find list="xray-envs" key="LOG_LEVEL"] value="warn" }

:if ([:len [/container/envs find where list="xray-envs" and key="DEBUG_HOLD"]] = 0) do={
    /container/envs add list=xray-envs key=DEBUG_HOLD value="0"
}

# --- 7. Чистим устаревшие GEO_* переменные, если остались ---
:foreach k in={"GEO_MAX_AGE_DAYS";"GEO_SKIP_DOWNLOAD"} do={
    :if ([:len [/container/envs find where list="xray-envs" and key=$k]] > 0) do={
        /container/envs remove [find list="xray-envs" key=$k]
        :log info "02: removed obsolete env $k"
    }
}

# --- 8. Удаляем старый контейнер (для подтягивания свежего образа) ---
:if ([:len [/container find where name=$containerName]] > 0) do={
    :log info "02: removing existing container"
    :do { /container/stop [find name=$containerName] } on-error={}
    :delay 3s
    /container/remove [find name=$containerName]
    :delay 2s
}

# --- 9. Создаём контейнер ---
/container add \
    name=$containerName \
    remote-image=$imageName \
    interface=$vethName \
    mountlists=custom-rules \
    envlist=xray-envs \
    privileged=yes \
    start-on-boot=yes \
    restart-policy=always \
    restart-interval=30s \
    restart-max-count=0 \
    logging=yes \
    comment="Xray gateway (VLESS+Reality + hev-socks5-tunnel)"

:log info "02: created container $containerName"

# --- 10. Запуск ---
:delay 2s
/container start [find name=$containerName]
:log info "02: container start issued"

:delay 10s
:log info "02: container status:"
/container print detail where name=$containerName
:log info "02: container setup complete"
