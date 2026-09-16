# NAT уже покрыт LAN_SUBNET; добавляем только forward-доступ и QUIC-drop.
# КРИТИЧНО: новые правила должны стоять ВЫШЕ "Drop all other".
:log info "05: start"
:local anchor [/ip firewall filter find comment="forward: Drop all other (Default Deny)"]

:if ([:len [/ip firewall filter find where comment="Allow LAN to Xray container"]] = 0) do={
    /ip firewall filter add chain=forward action=accept \
        in-interface=bridge_LAN out-interface=veth-xray \
        place-before=$anchor comment="Allow LAN to Xray container"
    :log info "05: forward LAN->Xray added"
}

# QUIC (UDP:443) помеченных соединений дропаем -> клиенты сразу идут по TCP
:if ([:len [/ip firewall filter find where comment="Block QUIC for proxied"]] = 0) do={
    /ip firewall filter add chain=forward action=drop protocol=udp dst-port=443 \
        in-interface=bridge_LAN connection-mark=xray-conn \
        place-before=$anchor comment="Block QUIC for proxied"
    :log info "05: QUIC drop added"
}
:log info "05: done"
