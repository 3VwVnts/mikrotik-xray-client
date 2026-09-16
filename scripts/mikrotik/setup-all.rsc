# ============================================================
# setup-all.rsc
# Последовательный запуск всех этапов настройки
# ============================================================
# ПЕРЕД ЗАПУСКОМ:
#   1. Открой 02-container.rsc, замени PLACEHOLDER_VLESS_URI
#      на свою реальную строку vless://...
#   2. Убедись, что все файлы 01..06 лежат в корне роутера
# ============================================================

:log info "=== Xray MikroTik setup: START ==="

:log info "=== Stage 01: bridge + veth + tmpfs ==="
/import file-name=01-bridge-veth.rsc
:delay 3s

:log info "=== Stage 02: container ==="
/import file-name=02-container.rsc
:delay 15s

:log info "=== Stage 03: routing table + DoH ==="
/import file-name=03-routing.rsc
:delay 2s

:log info "=== Stage 04: mangle (mark traffic) ==="
/import file-name=04-mangle.rsc
:delay 2s

:log info "=== Stage 05: NAT + forward ==="
/import file-name=05-nat-forward.rsc
:delay 2s

:log info "=== Stage 06: healthcheck ==="
/import file-name=06-healthcheck.rsc
:delay 2s

:log info "=== Xray MikroTik setup: DONE ==="
:log info "Проверка: /container print detail where name=xray-gateway"
:log info "Проверка: /log print where topics~\"container\""
:log info "Проверка: curl через LAN → https://ifconfig.me должен показать IP VPS"
