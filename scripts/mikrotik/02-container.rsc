# ============================================================
# 02-container.rsc
# Создание контейнера Xray + hev-socks5-tunnel
# ============================================================
# USER CONFIG — единственное место, где нужны правки
# ============================================================
:local vlessURI "PLACEHOLDER_VLESS_URI"
:local imageName "ghcr.io/3vwvnts/mikrotik-xray-client:latest"
:local containerName "xray-client"
:local vethName "veth-xray"
# ============================================================

:log info "02: starting container setup"

# --- 0. Проверка, что пользователь заменил VLESS_URI ---
:if ($vlessURI = "PLACEHOLDER_VLESS_URI") do={
    :log error "02: VLESS_URI not set. Edit the USER CONFIG block at the top of 02-container.rsc"
    :error "VLESS_URI placeholder not replaced"
}

# --- 1. Проверка veth ---
:if ([:len [/interface veth find where name=$vethName]] = 0) do={
    :log error "02: $vethName not found. Run 01-bridge-veth.rsc first."
    :error "veth missing"
}

# --- 2. Mount для geo ---
:if ([:len [/container/mounts find where list="geo"]] = 0) do={
    /container/mounts add list=geo src=geo dst=/var/lib/xray/geo
    :log info "02: added geo mount"
} else={
    :log info "02: geo mount exists"
}

# --- 3. Mount для custom-rules.json ---
:if ([:len [/container/mounts find where list="custom-rules"]] = 0) do={
    /container/mounts add list=custom-rules src=custom-rules.json dst=/etc/xray/custom-rules.json
    :log info "02: added custom-rules mount"
} else={
    :log info "02: custom-rules mount exists"
}

# --- 4. ENV: VLESS_URI ---
:if ([:len [/container/envs find where list="xray-envs" and key="VLESS_URI"]] = 0) do={
    /container/envs add list=xray-envs key=VLESS_URI value=$vlessURI
    :log info "02: added VLESS_URI env"
} else={
    /container/envs set [find list="xray-envs" key="VLESS_URI"] value=$vlessURI
    :log info "02: updated VLESS_URI env"
}

# --- 5. Остальные ENV ---
:if ([:len [/container/envs find where list="xray-envs" and key="PROXY_MODE"]] = 0) do={
    /container/envs add list=xray-envs key=PROXY_MODE value="hev-tunnel"
}
:if ([:len [/container/envs find where list="xray-envs" and key="GEO_MAX_AGE_DAYS"]] = 0) do={
    /container/envs add list=xray-envs key=GEO_MAX_AGE_DAYS value="3"
}
:if ([:len [/container/envs find where list="xray-envs" and key="LOG_LEVEL"]] = 0) do={
    /container/envs add list=xray-envs key=LOG_LEVEL value="info"
}
:if ([:len [/container/envs find where list="xray-envs" and key="DEBUG_HOLD"]] = 0) do={
    /container/envs add list=xray-envs key=DEBUG_HOLD value="0"
}

# --- 6. Удаляем старый контейнер (чтобы подтянулся свежий образ) ---
:if ([:len [/container find where name=$containerName]] > 0) do={
    :log info "02: removing existing container"
    :do { /container/stop [find name=$containerName] } on-error={}
    :delay 3s
    /container/remove [find name=$containerName]
    :delay 2s
}

# --- 7. Создаём контейнер ---
/container add \
    name=$containerName \
    remote-image=$imageName \
    interface=$vethName \
    mountlists=geo,custom-rules \
    envlist=xray-envs \
    privileged=yes \
    start-on-boot=yes \
    restart-policy=always \
    restart-interval=30s \
    restart-max-count=0 \
    logging=yes \
    comment="Xray client (VLESS+Reality + hev-socks5-tunnel)"

:log info "02: created container $containerName"

# --- 8. Запуск ---
:delay 2s
/container start [find name=$containerName]
:log info "02: container start issued"

:delay 10s
:log info "02: container status:"
/container print detail where name=$containerName

:log info "02: container setup complete"
