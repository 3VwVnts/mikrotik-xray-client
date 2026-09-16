# ============================================================
# 01-bridge-veth.rsc
# tmpfs, veth, custom-rules.json. Firewall/NAT/mangle не трогает.
# ============================================================
:log info "01: start"

# 1. tmpfs-диск docker
:if ([:len [/disk find where slot="docker"]] = 0) do={
    /disk add type=tmpfs tmpfs-max-size=200M slot=docker
    :delay 2s
    :log info "01: created tmpfs disk 'docker' (200M)"
}
/container/config set tmpdir="docker/tmp" layer-dir="docker/layers"

# 2. custom-rules.json — пересоздаём (валидный однострочный JSON)
:if ([:len [/file find where name="custom-rules.json"]] > 0) do={
    /file remove [find where name="custom-rules.json"]
}
/file add name="custom-rules.json" contents="{\"proxy_domains\":[],\"proxy_ips\":[],\"direct_domains\":[],\"direct_ips\":[]}"
:log info "01: custom-rules.json created"

# 3. veth
:if ([:len [/interface veth find where name="veth-xray"]] = 0) do={
    /interface veth add name=veth-xray address=172.17.0.2/24 gateway=172.17.0.1
    :log info "01: created veth-xray"
}

# 4. Gateway IP на veth
:if ([:len [/ip address find where interface="veth-xray" and address~"172.17.0.1"]] = 0) do={
    /ip address add address=172.17.0.1/24 interface=veth-xray comment="Xray container gateway"
    :log info "01: added 172.17.0.1/24 on veth-xray"
}

# 5. Подсеть контейнера в LAN_SUBNET -> NAT покрывается существующим masquerade
:if ([:len [/ip firewall address-list find where list="LAN_SUBNET" and address="172.17.0.0/24"]] = 0) do={
    /ip firewall address-list add list=LAN_SUBNET address=172.17.0.0/24 comment="Xray container subnet"
    :log info "01: LAN_SUBNET += 172.17.0.0/24"
}

# 6. veth в LAN-list
:if ([:len [/interface list member find where list="LAN" and interface="veth-xray"]] = 0) do={
    /interface list member add list=LAN interface=veth-xray comment="Xray container veth"
    :log info "01: veth-xray added to LAN list"
}

:log info "01: done"
