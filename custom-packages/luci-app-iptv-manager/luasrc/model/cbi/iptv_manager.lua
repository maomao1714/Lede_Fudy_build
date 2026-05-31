local m, m2, s, o

-- ══════════════════════════════════════════════════════════════
--  Map 1：全局控制 + msd_lite 配置  (/etc/config/iptv_manager)
-- ══════════════════════════════════════════════════════════════
m = Map("iptv_manager",
    translate("IPTV 管理器"),
    translate("统一管理 msd_lite 与 rtp2HTTPd，两套配置独立保存，随时可切换。"))

-- ── 状态栏 ──────────────────────────────────────────────────
m:section(SimpleSection).template = "iptv_manager/status"

-- ── 基本设置 ─────────────────────────────────────────────────
s = m:section(NamedSection, "global", "global", translate("基本设置"))
s.addremove = false
s.anonymous = true

o = s:option(Flag, "enabled", translate("启用 IPTV 服务"))
o.rmempty = false
o.default = "0"

o = s:option(ListValue, "program", translate("选择程序"),
    translate("选择后保存应用，下方自动切换对应配置区。"))
o:value("msd",       translate("msd_lite  —  轻量 UDP 组播转 HTTP"))
o:value("rtp2httpd", translate("rtp2HTTPd  —  功能完整的 IPTV HTTP 代理"))
o.rmempty = false
o.default = "rtp2httpd"

-- 注入 JS（切换两个区块显隐）
m:section(SimpleSection).template = "iptv_manager/toggle_js"

-- ── msd_lite 配置 ────────────────────────────────────────────
s = m:section(NamedSection, "msd", "msd",
    translate("msd_lite 配置"),
    translate("选择「msd_lite」时生效。"))
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
    translate("默认 4096"))
o.placeholder = "4096"
o.datatype    = "uinteger"
o.rmempty     = true

o = s:option(Value, "extra_args",
    translate("额外命令行参数"),
    translate("直接追加到 msd_lite 命令行末尾"))
o.placeholder = ""
o.rmempty     = true


-- ══════════════════════════════════════════════════════════════
--  Map 2：rtp2HTTPd 原生配置  (/etc/config/rtp2httpd)
--  由 JS 根据程序选择控制整块显隐（id = cbi-rtp2httpd）
-- ══════════════════════════════════════════════════════════════
m2 = Map("rtp2httpd",
    translate("rtp2HTTPd 配置"),
    translate("以下参数由 rtp2HTTPd 自身读取（/etc/config/rtp2httpd），选择「rtp2HTTPd」时生效。"))

s = m2:section(TypedSection, "rtp2httpd", "")
s.anonymous = true
s.addremove = false

-- ── 基本 ──────────────────────────────────────────────────
o = s:option(Value, "port",
    translate("HTTP 监听端口"),
    translate("客户端访问端口，默认 5140"))
o.placeholder = "5140"
o.datatype    = "port"
o.rmempty     = true

-- ── 接口配置 ──────────────────────────────────────────────
o = s:option(Flag, "advanced_interface_settings",
    translate("高级接口模式"),
    translate("关闭：所有流量走同一接口；开启：组播/FCC/RTSP/HTTP 分别指定接口"))
o.rmempty = true
o.default = "0"

-- 简单模式
o = s:option(Value, "upstream_interface",
    translate("上游接口（简单模式）"),
    translate("所有流量来源接口，例如 iptv 或 eth0.4"))
o.placeholder = "iptv"
o.rmempty     = true
o:depends("advanced_interface_settings", "0")

-- 高级模式
o = s:option(Value, "upstream_interface_multicast",
    translate("组播接口"),
    translate("接收 UDP/RTP 组播数据的接口"))
o.placeholder = "eth0"
o.rmempty     = true
o:depends("advanced_interface_settings", "1")

o = s:option(Value, "upstream_interface_fcc",
    translate("FCC 快速换台接口"),
    translate("Fast Channel Change 数据接口"))
o.placeholder = "eth1"
o.rmempty     = true
o:depends("advanced_interface_settings", "1")

o = s:option(Value, "upstream_interface_rtsp",
    translate("RTSP 接口"))
o.placeholder = "eth2"
o.rmempty     = true
o:depends("advanced_interface_settings", "1")

o = s:option(Value, "upstream_interface_http",
    translate("HTTP 上游接口"))
o.placeholder = "eth3"
o.rmempty     = true
o:depends("advanced_interface_settings", "1")

-- ── 性能 ──────────────────────────────────────────────────
o = s:option(Value, "maxclients",
    translate("最大客户端数"),
    translate("默认 5"))
o.placeholder = "5"
o.datatype    = "uinteger"
o.rmempty     = true

o = s:option(Value, "workers",
    translate("工作线程数"),
    translate("默认 1"))
o.placeholder = "1"
o.datatype    = "uinteger"
o.rmempty     = true

o = s:option(Value, "buffer_pool_max_size",
    translate("缓冲池大小（字节）"),
    translate("默认 16384"))
o.placeholder = "16384"
o.datatype    = "uinteger"
o.rmempty     = true

o = s:option(Value, "udp_rcvbuf_size",
    translate("UDP 接收缓冲区（字节）"),
    translate("默认 524288（512 KB）"))
o.placeholder = "524288"
o.datatype    = "uinteger"
o.rmempty     = true

o = s:option(Flag, "zerocopy_on_send",
    translate("Zero-Copy 发送优化"),
    translate("减少 CPU 内存复制，部分平台可提升性能"))
o.rmempty = true
o.default = "0"

-- ── Web 页面 ──────────────────────────────────────────────
o = s:option(Value, "status_page_path",
    translate("状态页面路径"),
    translate("rtp2HTTPd 内置状态页的访问路径，例如 /status"))
o.placeholder = "/status"
o.rmempty     = true

o = s:option(Value, "player_page_path",
    translate("Web 播放器路径"),
    translate("内置 Web 播放器的访问路径，例如 /player"))
o.placeholder = "/player"
o.rmempty     = true

-- ── M3U 频道列表 ──────────────────────────────────────────
o = s:option(Value, "external_m3u",
    translate("外部 M3U 播放列表 URL"),
    translate("从远程 URL 拉取频道列表，例如 https://example.com/playlist.m3u"))
o.placeholder = "https://example.com/playlist.m3u"
o.rmempty     = true

o = s:option(Value, "external_m3u_update_interval",
    translate("M3U 更新间隔（秒）"),
    translate("自动重拉 M3U 的周期，默认 7200 秒（2 小时）"))
o.placeholder = "7200"
o.datatype    = "uinteger"
o.rmempty     = true

-- ── HTTP / 安全 ───────────────────────────────────────────
o = s:option(Value, "hostname",
    translate("服务器主机名（可选）"),
    translate("HTTP 响应中使用的主机名，留空使用默认"))
o.placeholder = "somehost.example.com"
o.rmempty     = true

o = s:option(Flag, "xff",
    translate("转发 X-Forwarded-For"),
    translate("在 HTTP 请求中传递客户端真实 IP"))
o.rmempty = true
o.default = "0"

o = s:option(Value, "cors_allow_origin",
    translate("CORS 允许来源"),
    translate("跨域请求允许的来源，* 表示所有；留空禁用 CORS"))
o.placeholder = "*"
o.rmempty     = true

o = s:option(Value, "r2h_token",
    translate("访问令牌（可选）"),
    translate("设置后客户端访问须附带 token 参数，留空不验证"))
o.placeholder = "your-secret-token-here"
o.password    = true
o.rmempty     = true

-- ── 组播 / FCC ────────────────────────────────────────────
o = s:option(Value, "mcast_rejoin_interval",
    translate("组播重加入间隔（秒）"),
    translate("定期重新加入组播组，0 表示禁用"))
o.placeholder = "0"
o.datatype    = "uinteger"
o.rmempty     = true

o = s:option(Value, "fcc_listen_port_range",
    translate("FCC 监听端口范围"),
    translate("Fast Channel Change 使用的 UDP 端口范围，例如 40000-40100"))
o.placeholder = "40000-40100"
o.rmempty     = true

-- ── HTTP 代理 / RTSP ──────────────────────────────────────
o = s:option(Value, "http_proxy_user_agent",
    translate("HTTP 代理 User-Agent"),
    translate("拉取外部 M3U 或 HTTP 源时使用的 UA"))
o.placeholder = "rtp2httpd-http-proxy/1.0"
o.rmempty     = true

o = s:option(Value, "rtsp_user_agent",
    translate("RTSP User-Agent"),
    translate("RTSP 连接时使用的 UA"))
o.placeholder = "rtp2httpd/custom"
o.rmempty     = true

o = s:option(Value, "rtsp_stun_server",
    translate("RTSP STUN 服务器"),
    translate("RTSP NAT 穿透用 STUN 服务器地址"))
o.placeholder = "stun.miwifi.com"
o.rmempty     = true

-- ── FFmpeg ────────────────────────────────────────────────
o = s:option(Value, "ffmpeg_path",
    translate("FFmpeg 路径"),
    translate("视频截图/转码功能所需的 ffmpeg 二进制路径，默认 ffmpeg"))
o.placeholder = "ffmpeg"
o.rmempty     = true

o = s:option(Value, "ffmpeg_args",
    translate("FFmpeg 额外参数"))
o.placeholder = "-hwaccel none"
o.rmempty     = true

o = s:option(Flag, "video_snapshot",
    translate("启用视频截图功能"),
    translate("需要 FFmpeg 支持"))
o.rmempty = true
o.default = "0"

return m, m2
