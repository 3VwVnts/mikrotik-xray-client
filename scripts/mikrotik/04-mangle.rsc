# ============================================================
# 04-mangle.rsc
# Маркировка трафика LAN для Xray + MSS clamp
# ============================================================

:log info "04: starting mangle setup"

# --- 1. Создаём address-list с локальными сетями (исключения) ---
/ip firewall address-list
:if ([:len [find where list="LOCAL"]] = 0) do={
    add list=LOCAL address=192.168.10.0/24 comment="Local LAN"
    add list=LOCAL address=10.10.10.0/24 comment="WireGuard subnet"
    add list=LOCAL address=172.17.0.0/24 comment="Container subnet"
    add list=LOCAL address=224.0.0.0/4 comment="Multicast"
    add list=LOCAL address=192.168.10.1 comment="Router IP"
    :log info "04: created LOCAL address-list"
} else={
    :log info "04: LOCAL address-list already exists"
}

# --- 2. Находим правило, перед которым нужно вставить новые ---
:local placeBefore [/ip firewall mangle find comment="Mangle: Fix L2TP MSS Out"]

# --- 3. Помечаем соединения из LAN (кроме локальных) ---
:local markConnRule [/ip firewall mangle find comment="Mark LAN connections for Xray"]
:if ([:len $markConnRule] = 0) do={
    :if ([:len $placeBefore] > 0) do={
        /ip firewall mangle add \
            chain=prerouting \
            in-interface=bridge_LAN \
            dst-address-list=!LOCAL \
            connection-mark=no-mark \
            action=mark-connection \
            new-connection-mark=xray-conn \
            passthrough=yes \
            place-before=$placeBefore \
            comment="Mark LAN connections for Xray"
    } else={
        /ip firewall mangle add \
            chain=prerouting \
            in-interface=bridge_LAN \
            dst-address-list=!LOCAL \
            connection-mark=no-mark \
            action=mark-connection \
            new-connection-mark=xray-conn \
            passthrough=yes \
            comment="Mark LAN connections for Xray"
    }
    :log info "04: added mark-connection rule for LAN"
}

# --- 4. Помечаем маршрут для этих соединений ---
:local markRouteRule [/ip firewall mangle find comment="Route marked connections to Xray"]
:if ([:len $markRouteRule] = 0) do={
    :if ([:len $placeBefore] > 0) do={
        /ip firewall mangle add \
            chain=prerouting \
            connection-mark=xray-conn \
            action=mark-routing \
            new-routing-mark=xray \
            passthrough=no \
            place-before=$placeBefore \
            comment="Route marked connections to Xray"
    } else={
        /ip firewall mangle add \
            chain=prerouting \
            connection-mark=xray-conn \
            action=mark-routing \
            new-routing-mark=xray \
            passthrough=no \
            comment="Route marked connections to Xray"
    }
    :log info "04: added mark-routing rule for Xray"
}

# --- 5. MSS clamp для veth-xray (и входящий, и исходящий) ---
:local mssOut [/ip firewall mangle find comment="MSS clamp out to Xray"]
:if ([:len $mssOut] = 0) do={
    /ip firewall mangle add \
        chain=forward \
        action=change-mss \
        new-mss=clamp-to-pmtu \
        protocol=tcp \
        tcp-flags=syn \
        out-interface=veth-xray \
        passthrough=yes \
        comment="MSS clamp out to Xray"
    :log info "04: added MSS clamp out to Xray"
}

:local mssIn [/ip firewall mangle find comment="MSS clamp in from Xray"]
:if ([:len $mssIn] = 0) do={
    /ip firewall mangle add \
        chain=forward \
        action=change-mss \
        new-mss=clamp-to-pmtu \
        protocol=tcp \
        tcp-flags=syn \
        in-interface=veth-xray \
        passthrough=yes \
        comment="MSS clamp in from Xray"
    :log info "04: added MSS clamp in from Xray"
}

# --- 6. Обновляем FastTrack, чтобы он не обходил маркировку ---
:local fastTrack [/ip firewall filter find comment="FastTrack: LAN->WAN"]
:if ([:len $fastTrack] > 0) do={
    /ip firewall filter set $fastTrack connection-mark=no-mark
    :log info "04: updated FastTrack rule with connection-mark=no-mark"
} else={
    :log warning "04: FastTrack rule not found (comment='FastTrack: LAN->WAN')"
}

:log info "04: mangle setup complete"
