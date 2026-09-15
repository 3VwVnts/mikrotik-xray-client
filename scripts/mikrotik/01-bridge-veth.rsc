# ============================================================
# 01-bridge-veth.rsc
# tmpfs + veth + вспомогательные сущности для контейнера Xray
# ============================================================
# Идемпотентен. Не трогает firewall, NAT, routing.
# ============================================================

:log info "01: starting bridge-veth setup"

# ------------------------------------------------------------
# 1. tmpfs-диск docker
# ------------------------------------------------------------
:if ([:len [/disk find where slot="docker"]] = 0) do={
    /disk add type=tmpfs tmpfs-max-size=200M slot=docker
    :delay 2s
    :log info "01: created tmpfs disk 'docker' (200M)"
} else={
    :log info "01: disk 'docker' already exists"
}

/container/config set tmpdir="docker/tmp" layer-dir="docker/layers"
:log info "01: container config → tmpdir=docker/tmp, layer-dir=docker/layers"

# ------------------------------------------------------------
# 2. Директория geo
# ------------------------------------------------------------
:if ([:len [/file find where name="geo"]] = 0) do={
    /file add name=geo type=directory
    :log info "01: created /geo directory"
} else={
    :log info "01: /geo already exists"
}

# ------------------------------------------------------------
# 3. custom-rules.json — УДАЛЯЕМ старый и создаём валидный
# ------------------------------------------------------------
# ВАЖНО: содержимое пишется БЕЗ \n, всё в одну строку.
# Иначе RouterOS записывает escape-последовательности буквально,
# и jq потом падает на invalid JSON.
:if ([:len [/file find where name="custom-rules.json"]] > 0) do={
    /file remove [find where name="custom-rules.json"]
    :log info "01: removed old custom-rules.json"
}

/file add name="custom-rules.json" contents="{\"proxy_domains\":[],\"proxy_ips\":[],\"direct_domains\":[],\"direct_ips\":[]}"
:log info "01: created /custom-rules.json (valid one-line JSON)"

# ------------------------------------------------------------
# 4. veth интерфейс
# ------------------------------------------------------------
:if ([:len [/interface veth find where name="veth-xray"]] = 0) do={
    /interface veth add \
        name=veth-xray \
        address=172.17.0.2/24 \
        gateway=172.17.0.1
    :log info "01: created veth-xray"
} else={
    :log info "01: veth-xray already exists"
}

# ------------------------------------------------------------
# 5. Gateway IP на veth-xray
# ------------------------------------------------------------
:if ([:len [/ip address find where interface="veth-xray" and address~"172.17.0.1"]] = 0) do={
    /ip address add \
        address=172.17.0.1/24 \
        interface=veth-xray \
        comment="Xray container gateway"
    :log info "01: added 172.17.0.1/24 on veth-xray"
} else={
    :log info "01: gateway IP already present"
}

# ------------------------------------------------------------
# 6. Container subnet → LAN_SUBNET (для NAT)
# ------------------------------------------------------------
:if ([:len [/ip firewall address-list find where list="LAN_SUBNET" and address="172.17.0.0/24"]] = 0) do={
    /ip firewall address-list add \
        list=LAN_SUBNET \
        address=172.17.0.0/24 \
        comment="Xray container subnet"
    :log info "01: added 172.17.0.0/24 to LAN_SUBNET"
} else={
    :log info "01: 172.17.0.0/24 already in LAN_SUBNET"
}

# ------------------------------------------------------------
# 7. interface-lists WAN / LAN
# ------------------------------------------------------------
:if ([:len [/interface list member find where list="WAN" and interface="freedom-l2tp"]] = 0) do={
    /interface list member add list=WAN interface=freedom-l2tp comment="WAN via L2TP"
    :log info "01: added freedom-l2tp to WAN"
}
:if ([:len [/interface list member find where list="WAN" and interface="ether1"]] = 0) do={
    /interface list member add list=WAN interface=ether1 comment="WAN direct"
    :log info "01: added ether1 to WAN"
}
:if ([:len [/interface list member find where list="LAN" and interface="bridge_LAN"]] = 0) do={
    /interface list member add list=LAN interface=bridge_LAN comment="LAN bridge"
    :log info "01: added bridge_LAN to LAN"
}
# veth-xray в LAN-list — чтобы forward LAN→L2TP пропускал контейнер наружу
:if ([:len [/interface list member find where list="LAN" and interface="veth-xray"]] = 0) do={
    /interface list member add list=LAN interface=veth-xray comment="Xray container veth"
    :log info "01: added veth-xray to LAN list"
}

# ------------------------------------------------------------
# 8. Проверка
# ------------------------------------------------------------
:log info "01: === disk status ==="
/disk print
:log info "01: === veth status ==="
/interface veth print brief where name="veth-xray"
:log info "01: === container config ==="
/container/config print
:log info "01: bridge-veth setup complete"
