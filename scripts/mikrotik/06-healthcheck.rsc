# ============================================================
# 06-healthcheck.rsc
# Health-check контейнера Xray + scheduler
# ============================================================

:log info "06: starting healthcheck setup"

:local containerName "xray-client"

# --- 1. Убеждаемся, что restart-policy включён ---
:if ([:len [/container find where name=$containerName]] > 0) do={
    /container set [find name=$containerName] \
        restart-policy=always \
        restart-interval=30s \
        restart-max-count=0
    :log info "06: container restart-policy set to always"
} else={
    :log error "06: container $containerName not found"
    :error "container missing"
}

# --- 2. Скрипт проверки (сохраняем как отдельный скрипт в /system script) ---
# Он будет вызываться scheduler'ом каждые 5 минут.
:local hcName "xray-healthcheck"
:if ([:len [/system script find where name=$hcName]] > 0) do={
    /system script remove [find name=$hcName]
    :log info "06: removed old $hcName script"
}

/system script add name=$hcName source={
    :local containerName "xray-client"
    :local c [/container find where name=$containerName]
    :if ([:len $c] = 0) do={
        :log warning "hc: container $containerName not found"
    } else={
        :local status [/container get $c status]
        :if ($status != "running") do={
            :log warning "hc: container status=$status, restarting"
            /container stop $c
            :delay 2s
            /container start $c
        } else={
            :log info "hc: container is running (OK)"
        }
    }
}
:log info "06: created script $hcName"

# --- 3. Scheduler: запускать каждые 5 минут ---
:local schName "xray-healthcheck"
:if ([:len [/system scheduler find where name=$schName]] > 0) do={
    /system scheduler remove [find name=$schName]
    :log info "06: removed old scheduler $schName"
}

/system scheduler add \
    name=$schName \
    interval=5m \
    start-time=startup \
    on-event="/system script run $hcName" \
    policy=read,write,test \
    comment="Health-check for Xray container"

:log info "06: created scheduler $schName (every 5m)"

:log info "06: healthcheck setup complete"
