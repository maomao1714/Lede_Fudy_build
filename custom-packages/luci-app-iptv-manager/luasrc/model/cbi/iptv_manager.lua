local m, s, o

m = Map("iptv_manager",
    translate("IPTV 管理器"),
    translate("统一管理 msd_lite 与 rtp2HTTPd，选择程序后保存生效，两套配置独立互不干扰。"))

-- ══ 基本设置 ══════════════════════════════════════════════
s = m:section(NamedSection, "global", "global", translate("基本设置"))
s.addremove = false
s.anonymous = true

o = s:option(Flag, "enabled", translate("启用 IPTV 服务"))
o.rmempty = false
o.default = "0"

o = s:option(ListValue, "program", translate("选择程序"),
    translate("选择后保存，下方自动切换对应配置区。两套配置均已保存，随时可切换。"))
o:value("msd",       translate("msd_lite  —  轻量组播转发"))
o:value("rtp2httpd", translate("rtp2HTTPd  —  HTTP 流代理（功能更丰富）"))
o.rmempty = false
o.default = "rtp2httpd"

-- 注入切换 JS
m:section(SimpleSection).template = "iptv_manager/toggle_js"

-- ══ msd_lite 配置 ═════════════════════════════════════════
s = m:section(NamedSection, "msd", "msd",
    translate("msd_lite 配置"),
    translate("以下参数仅当上方选择「msd_lite」时生效。"))
s.addremove = false

o = s:option(Value, "interface",
    translate("组播来源接口"),
    translate("接收 IPTV 组播包的网络接口，例如 eth0.4"))
o.placeholder = "eth0"
o.rmempty     = false

o = s:option(Value, "port",
    translate("HTTP 输出端口"),
    translate("客户端通过 http://路由器IP:<端口>/组播IP:port 拉流"))
o.placeholder = "4022"
o.datatype    = "port"
o.rmempty     = false

o = s:option(Value, "source_prefix",
    translate("组播源地址前缀（可选）"),
    translate("只转发指定前缀的组播组，例如 239.0.0.0/8；留空转发全部"))
o.placeholder = "239.0.0.0/8"
o.rmempty     = true

o = s:option(Value, "buffer",
    translate("UDP 缓冲区大小（字节）"),
    translate("接收 UDP 数据包的缓冲区，默认 4096"))
o.placeholder = "4096"
o.datatype    = "uinteger"
o.rmempty     = true

o = s:option(Value, "extra_args",
    translate("额外命令行参数"),
    translate("直接追加到 msd_lite 命令行末尾"))
o.placeholder = ""
o.rmempty     = true

-- ══ rtp2HTTPd 配置 ════════════════════════════════════════
s = m:section(NamedSection, "rtp2httpd", "rtp2httpd",
    translate("rtp2HTTPd 配置"),
    translate("以下参数仅当上方选择「rtp2HTTPd」时生效。"))
s.addremove = false

o = s:option(Value, "http_addr",
    translate("HTTP 监听地址"),
    translate("HTTP 服务绑定 IP，0.0.0.0 表示所有接口"))
o.placeholder = "0.0.0.0"
o.datatype    = "ipaddr"
o.rmempty     = false

o = s:option(Value, "http_port",
    translate("HTTP 监听端口"),
    translate("播放器访问 http://路由器IP:<端口>/... 拉取直播流"))
o.placeholder = "8080"
o.datatype    = "port"
o.rmempty     = false

o = s:option(Value, "interface",
    translate("组播来源接口"),
    translate("加入组播组时绑定的接口，例如 eth0.4"))
o.placeholder = "eth0"
o.rmempty     = false

o = s:option(Value, "source_ip",
    translate("组播源 IP 过滤（可选）"),
    translate("只转发来自指定 IP 的组播数据；留空不过滤"))
o.placeholder = ""
o.datatype    = "ipaddr"
o.rmempty     = true

o = s:option(Value, "buffer",
    translate("UDP → HTTP 缓冲区（字节）"),
    translate("建议 65536（64K）或更大，减少卡顿"))
o.placeholder = "65536"
o.datatype    = "uinteger"
o.rmempty     = true

o = s:option(Value, "max_clients",
    translate("最大同时连接客户端"),
    translate("0 表示不限制"))
o.placeholder = "10"
o.datatype    = "uinteger"
o.rmempty     = true

o = s:option(Value, "playlist",
    translate("M3U 频道列表文件（可选）"),
    translate("启用后可按频道名访问流；留空则只能按 IP:端口 访问"))
o.placeholder = "/etc/rtp2httpd/channels.m3u"
o.rmempty     = true

o = s:option(Flag, "udpxy_compat",
    translate("启用 udpxy 兼容 URL"),
    translate("开启后支持 /udp/组播IP:端口 格式，已配置 udpxy 的 m3u 无需改地址"))
o.rmempty = true
o.default = "0"

o = s:option(Value, "url_prefix",
    translate("HTTP URL 前缀（可选）"),
    translate("例如填 /iptv 后访问：http://路由器:8080/iptv/239.x.x.x:port"))
o.placeholder = ""
o.rmempty     = true

o = s:option(ListValue, "log_level",
    translate("日志级别"),
    translate("调试时选 debug；正常运行推荐 warning"))
o:value("error",   "error   — 仅错误")
o:value("warning", "warning — 错误+警告（推荐）")
o:value("info",    "info    — 详细信息")
o:value("debug",   "debug   — 全量调试")
o.default = "warning"
o.rmempty = true

o = s:option(Value, "extra_args",
    translate("额外命令行参数"),
    translate("直接追加到 rtp2httpd 命令行末尾"))
o.placeholder = ""
o.rmempty     = true

return m
