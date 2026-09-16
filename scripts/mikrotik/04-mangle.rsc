# split только для xray-domains. VPS/локальные сети -> bypass.
:log info "04: start"

/ip firewall address-list
:if ([:len [find where list="LOCAL"]] = 0) do={
    add list=LOCAL address=192.168.10.0/24 comment="Local LAN"
    add list=LOCAL address=10.10.10.0/24 comment="WireGuard"
    add list=LOCAL address=172.17.0.0/24 comment="Container subnet"
    add list=LOCAL address=198.18.0.0/15 comment="Container tun net"
    add list=LOCAL address=224.0.0.0/4 comment="Multicast"
    add list=LOCAL address=255.255.255.255/32 comment="DHCP broadcast"
    add list=LOCAL address=192.168.10.1 comment="Router IP"
    add list=LOCAL address=151.243.169.168 comment="VPS - loop guard"
    :log info "04: LOCAL list created"
}

# --- Список прокси-доменов (FQDN, RouterOS резолвит сам) ---
:if ([:len [find where list="xray-domains"]] = 0) do={
    :foreach d in={"youtube.com";"www.youtube.com";"youtu.be";"googlevideo.com";"ytimg.com";"ggpht.com";"youtubei.googleapis.com";"google.com";"www.google.com";"gstatic.com";"googleapis.com";"googleusercontent.com";"gvt1.com";"instagram.com";"www.instagram.com";"cdninstagram.com";"facebook.com";"fbcdn.net";"whatsapp.com";"whatsapp.net";"openai.com";"chatgpt.com";"oaistatic.com";"oaiusercontent.com";"anthropic.com";"claude.ai";"twitter.com";"x.com";"twimg.com";"netflix.com";"nflxvideo.net";"nflximg.net";"spotify.com";"scdn.co";"discord.com";"discordapp.com";"discordapp.net";"discord.media";"cloudflare.com";"www.cloudflare.com"} do={
        /ip firewall address-list add list=xray-domains address=$d
    }
    :log info "04: xray-domains list created"
}

# --- Разметка (in-interface обязателен - защита от петли) ---
:if ([:len [/ip firewall mangle find where comment="xray-split: mark proxy domains"]] = 0) do={
    /ip firewall mangle add chain=prerouting in-interface=bridge_LAN \
        dst-address-list=xray-domains connection-mark=no-mark \
        action=mark-connection new-connection-mark=xray-conn passthrough=yes \
        comment="xray-split: mark proxy domains"
}
:if ([:len [/ip firewall mangle find where comment="xray-split: route to container"]] = 0) do={
    /ip firewall mangle add chain=prerouting in-interface=bridge_LAN \
        connection-mark=xray-conn action=mark-routing new-routing-mark=xray \
        passthrough=no comment="xray-split: route to container"
}

# --- MSS clamp для veth (tun0 MTU 1420 -> MSS 1380) ---
:if ([:len [/ip firewall mangle find where comment="MSS clamp out to Xray"]] = 0) do={
    /ip firewall mangle add chain=forward action=change-mss new-mss=1380 passthrough=yes \
        tcp-flags=syn protocol=tcp out-interface=veth-xray comment="MSS clamp out to Xray"
}
:if ([:len [/ip firewall mangle find where comment="MSS clamp in from Xray"]] = 0) do={
    /ip firewall mangle add chain=forward action=change-mss new-mss=1380 passthrough=yes \
        tcp-flags=syn protocol=tcp in-interface=veth-xray comment="MSS clamp in from Xray"
}
:log info "04: done"
