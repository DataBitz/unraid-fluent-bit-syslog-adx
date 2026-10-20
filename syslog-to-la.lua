local facilities = {
    [0] = "kern", [1] = "user", [2] = "mail", [3] = "daemon",
    [4] = "auth", [5] = "syslog", [6] = "lpr", [7] = "news",
    [8] = "uucp", [9] = "cron", [10] = "authpriv", [11] = "ftp",
    [12] = "ntp", [13] = "logaudit", [14] = "logalert", [15] = "cron2",
    [16] = "local0", [17] = "local1", [18] = "local2", [19] = "local3",
    [20] = "local4", [21] = "local5", [22] = "local6", [23] = "local7"
}

local severities = {
    [0] = "emerg", [1] = "alert", [2] = "crit", [3] = "err",
    [4] = "warning", [5] = "notice", [6] = "info", [7] = "debug"
}

function transform_syslog(tag, timestamp, record)
    local pri = tonumber(record["pri"]) or 13
    local fac_num = math.floor(pri / 8)
    local sev_num = pri % 8
    local host = record["host"] or record["hostname"] or "unknown"
    local ident = record["ident"] or record["appname"] or record["app_name"] or ""
    local pid = tonumber(record["pid"] or record["procid"])
    local msg = record["message"] or record["msg"] or ""

    local new_record = {
        SourceSystem      = "FluentBit",
        CollectorHostName = os.getenv("HOSTNAME") or "fluentbit-forwarder",
        Computer          = host,
        HostName          = host,
        HostIP            = record["host_ip"] or "",
        Facility          = facilities[fac_num] or tostring(fac_num),
        SeverityLevel     = severities[sev_num] or tostring(sev_num),
        ProcessName       = ident,
        ProcessID         = pid,
        SyslogMessage     = msg,
        Type              = "Syslog"
    }

    return 2, timestamp, new_record
end