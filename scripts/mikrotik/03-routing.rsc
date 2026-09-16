# только таблица и маршрут. DNS не трогаем (Яндекс уже настроен).
:log info "03: start"
:if ([:len [/routing table find where name="xray"]] = 0) do={
    /routing table add name=xray fib
}
:if ([:len [/ip route find where routing-table="xray" and dst-address="0.0.0.0/0"]] = 0) do={
    /ip route add dst-address=0.0.0.0/0 gateway=172.17.0.2 routing-table=xray \
        check-gateway=ping distance=1 comment="Xray container default route"
}
:log info "03: done"
