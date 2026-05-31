#!/bin/bash
# DIY 脚本第一部分：添加自定义软件源
# 运行时机：在 LEDE 源码目录内，feeds update 执行之前

set -euo pipefail

# ─── 自定义 Feeds ─────────────────────────────────────────

# Lucky（内网穿透）
echo "src-git lucky https://github.com/gdy666/luci-app-lucky.git" \
    >> feeds.conf.default

# Qmodem（5G/4G 模组管理）
echo "src-git qmodem https://github.com/FUjr/modem_feeds.git;main" \
    >> feeds.conf.default

# rtp2HTTPd（RTP/UDP 组播 → HTTP 代理）
echo "src-git rtp2httpd https://github.com/stackia/rtp2httpd.git" \
    >> feeds.conf.default

# ─── 直接克隆到 package 目录（不走 feeds）────────────────

# msd_lite：轻量级 UDP 组播 → HTTP 转发（ximiTech 版）
git clone --depth=1 \
    https://github.com/ximiTech/msd_lite \
    package/msd_lite

# 删除官方自带 init.d，由本仓库统一 IPTV 管理脚本接管
rm -f package/msd_lite/files/etc/init.d/msd_lite 2>/dev/null || true

# ─── 复制仓库内自定义包 ──────────────────────────────────

# IPTV 管理器 LuCI 界面（msd_lite / rtp2HTTPd 二合一）
cp -r "${GITHUB_WORKSPACE}/custom-packages/luci-app-iptv-manager" \
      package/luci-app-iptv-manager

# ─── 完成 ────────────────────────────────────────────────

echo "✅ 软件源配置完成"
echo ""
echo "=== feeds.conf.default ==="
cat feeds.conf.default
