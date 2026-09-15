# ============================================================
# 02-container.rsc
# Создание контейнера и запуск Xray
# ============================================================
# !!! ОБЯЗАТЕЛЬНО: замени PLACEHOLDER_VLESS_URI на свою
#     реальную строку vless://... ПЕРЕД импортом !!!
# ============================================================

:log info "02: starting container setup"

# --- 0. Проверяем veth-xray ---
:if ([:len [/interface veth find where name="veth-xray"]] = 0) do={
    :log error "02: veth-xray not found. Run 01-bridge-veth.rsc first."
    :error "veth-xray missing"
}

# --- 1. Значение VLESS_URI (ЗАМЕНИ ПЕРЕД ИМПОРТОМ!) ---
:local vlessURI "PLACEHOLDER_VLESS_URI"

# Проверка: если плейсхолдер не заменён — стоп
:if ($vlessURI = "PLACEHOLDER_VLESS_URI") do={
    :log error "02: VLESS_URI not set. Edit 02-container.rsc and replace PLACEHOLDER_VLESS_URI"
    :error "VLESS_URI placeholder not replaced"
}

# --- 2. Mount для geo-кэша ---
:if ([:len [/container/mounts find where list="geo"]] = 0) do={
    /container/mounts add list=geo src=geo dst=/var/lib/xray/geo
    :log info "02: added geo mount"
} else={
    :log info "02: geo mount already exists"
}

# --- 3. Mount для custom-rules.json ---
:if ([:len [/container/mounts find where list="custom-rules"]] = 0) do={
    /container/mounts add list=custom-rules src=custom-rules.json dst=/etc/xray/custom-rules.json
    :log info "02: added custom-rules mount"
} else={
    :log info "02: custom-rules mount already exists"
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
    /container/envs add list=xray-envs key=PROXY_MODE value="tun2socks"
}
:if ([:len [/container/envs find where list="xray-envs" and key="GEO_MAX_AGE_DAYS"]] = 0) do={
    /container/envs add list=xray-envs key=GEO_MAX_AGE_DAYS value="3"
}
:if ([:len [/container/envs find where list="xray-envs" and key="LOG_LEVEL"]] = 0) do={
    /container/envs add list=xray-envs key=LOG_LEVEL value="warning"
}

# --- 6. Если контейнер уже есть — удаляем, чтобы пересоздать с privileged ---
:if ([:len [/container find where name="xray-client"]] > 0) do={
    :log info "02: removing existing container to recreate with privileged=yes"
    :do { /container/stop [find name="xray-client"] } on-error={}
    :delay 3s
    /container/remove [find name="xray-client"]
    :delay 2s
}

# --- 7. Создаём контейнер ---
/container add \
    name="xray-client" \
    remote-image="ghcr.io/3vwvnts/mikrotik-xray-client:latest" \
    interface=veth-xray \
    mountlists=geo,custom-rules \
    envlist=xray-envs \
    privileged=yes \
    start-on-boot=yes \
    logging=yes \
    comment="Xray client (VLESS+Reality + tun2socks)"
:log info "02: created container xray-client"

# --- 8. Запуск ---
:delay 2s
/container start [find name="xray-client"]
:log info "02: container start issued"

:delay 8s
:log info "02: container status:"
/container print detail where name="xray-client"

:log info "02: container setup complete. Check status with: /container print detail where name=xray-client"
