# ============================================================
# 05-nat-forward.rsc
# NAT для контейнера + правила forward
# ============================================================

:log info "05: starting NAT/forward setup"

# --- 1. NAT для контейнера (172.17.0.0/24 через L2TP) ---
:if ([:len [/ip firewall nat find comment="NAT Xray container to L2TP"]] = 0) do={
    /ip firewall nat add \
        chain=srcnat \
        action=masquerade \
        src-address=172.17.0.0/24 \
        out-interface=freedom-l2tp \
        comment="NAT Xray container to L2TP"
    :log info "05: added NAT rule for container"
} else={
    :log info "05: NAT rule for container already exists"
}

# --- 2. Forward: LAN -> Xray (veth-xray) ---
:if ([:len [/ip firewall filter find comment="Allow LAN to Xray container"]] = 0) do={
    /ip firewall filter add \
        chain=forward \
        action=accept \
        in-interface=bridge_LAN \
        out-interface=veth-xray \
        comment="Allow LAN to Xray container"
    :log info "05: added forward LAN -> Xray"
}

# --- 3. Forward: Xray -> LAN (обратный трафик) ---
:if ([:len [/ip firewall filter find comment="Allow Xray container to LAN"]] = 0) do={
    /ip firewall filter add \
        chain=forward \
        action=accept \
        in-interface=veth-xray \
        out-interface=bridge_LAN \
        comment="Allow Xray container to LAN"
    :log info "05: added forward Xray -> LAN"
}

# --- 4. Forward: Xray -> WAN (L2TP) для выхода в интернет ---
:if ([:len [/ip firewall filter find comment="Allow Xray container to L2TP"]] = 0) do={
    /ip firewall filter add \
        chain=forward \
        action=accept \
        in-interface=veth-xray \
        out-interface=freedom-l2tp \
        comment="Allow Xray container to L2TP"
    :log info "05: added forward Xray -> L2TP"
}

# --- 5. Forward: WAN -> Xray (обратный трафик из интернета) ---
:if ([:len [/ip firewall filter find comment="Allow L2TP to Xray container"]] = 0) do={
    /ip firewall filter add \
        chain=forward \
        action=accept \
        in-interface=freedom-l2tp \
        out-interface=veth-xray \
        comment="Allow L2TP to Xray container"
    :log info "05: added forward L2TP -> Xray"
}

:log info "05: NAT/forward setup complete"
