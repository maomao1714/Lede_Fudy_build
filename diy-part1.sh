#!/bin/bash
# =====================================================
# DIY 脚本第一部分
# 在 feeds update 之前执行
#
# 注意：LEDE 主线已原生支持 WH3000 eMMC，
# 此处只添加第三方软件源，不做任何设备补丁。
# =====================================================

set -e

# --- Lucky（内网穿透 + DDNS）---
echo "src-git lucky https://github.com/gdy666/luci-app-lucky.git" \
    >> feeds.conf.default

# --- Qmodem（4G/5G 模块管理）---
echo "src-git qmodem https://github.com/FUjr/modem_feeds.git;main" \
    >> feeds.conf.default

# --- rtp2httpd（IPTV 组播转单播，支持 FCC 快速换台）---
echo "src-git rtp2httpd https://github.com/stackia/rtp2httpd.git" \
    >> feeds.conf.default

echo ">>> feeds.conf.default 当前内容："
cat feeds.conf.default
echo ">>> 软件源添加完成"
