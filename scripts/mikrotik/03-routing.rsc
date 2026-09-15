# ============================================================
# 03-routing.rsc
# Таблица маршрутизации для Xray + DoH
# ============================================================

:log info "03: starting routing setup"

# --- 1. Создаём таблицу маршрутизации xray ---
:if ([:len [/routing table find where name="xray"]] = 0) do={
    /routing table add name=xray fib
    :log info "03: created routing table 'xray'"
} else={
    :log info "03: routing table 'xray' already exists"
}

# --- 2. Маршрут по умолчанию через veth-xray (IP контейнера 172.17.0.2) ---
:if ([:len [/ip route find where routing-table="xray" and dst-address="0.0.0.0/0"]] = 0) do={
    /ip route add \
        dst-address=0.0.0.0/0 \
        gateway=172.17.0.2 \
        routing-table=xray \
        check-gateway=ping \
        distance=1 \
        comment="Xray container default route"
    :log info "03: added default route via 172.17.0.2 to table 'xray'"
} else={
    :log info "03: default route to 'xray' already exists"
}

# --- 3. Настройка DoH (Cloudflare через IP, без проверки сертификата) ---
# Это защищает DNS-запросы от подмены провайдером.
/ip dns set \
    use-doh-server=https://1.1.1.1/dns-query \
    verify-doh-cert=no \
    servers="" \
    allow-remote-requests=yes
:log info "03: DoH configured (Cloudflare via 1.1.1.1)"

:log info "03: routing setup complete"
