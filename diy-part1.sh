#!/bin/bash

echo "========================================"
echo " DIY Part 1 - 配置软件源"
echo "========================================"

# ── 添加自定义 Feeds ─────────────────────────
echo "src-git lucky https://github.com/gdy666/luci-app-lucky.git" \
    >> feeds.conf.default
echo "src-git qmodem https://github.com/FUjr/modem_feeds.git;main" \
    >> feeds.conf.default
echo "src-git rtp2httpd https://github.com/stackia/rtp2httpd.git" \
    >> feeds.conf.default

# ── 克隆 msd_lite ────────────────────────────
git clone --depth=1 \
    https://github.com/ximiTech/msd_lite \
    package/msd_lite
rm -f package/msd_lite/files/etc/init.d/msd_lite 2>/dev/null || true

# ── 复制自定义 LuCI 插件 ─────────────────────
cp -r "${GITHUB_WORKSPACE}/custom-packages/luci-app-iptv-manager" \
    package/luci-app-iptv-manager

# ════════════════════════════════════════════════════════════════
#  清理 backport-6.6 冲突 patches（700–799 段）
# 清理 hack-6.6 Aquantia 冲突补丁
HACK_DIR="target/linux/generic/hack-6.6"

if [ -d "$HACK_DIR" ]; then
    rm -f "$HACK_DIR"/*aquantia*.patch 2>/dev/null || true
    echo ">>> ✅ 已清理 hack-6.6 Aquantia patch"
fi
#  根因：LEDE 的 700–799 编号 patch 均为将 Linux 6.7/6.8 的 net/phy
#        驱动改动回移至 6.6 分支的 backport。随着 6.6.x stable 持续
#        更新（当前 6.6.142），这些改动已被原生合入内核，backport patch
#        会重复创建/修改文件，导致 toolchain/kernel-headers 编译失败。
#
#  已知冲突 patch（陆续出现，一次性全清）：
#    702-01-v6.7-net-phy-aquantia-move-to-separate-directory.patch
#    707-v6.8-02-net-phy-at803x-move-disable-WOL-to-specific-at8031-p.patch
#    ...（同段其余 patch 可能随内核更新继续出现）
#
#  安全性：700–799 段均为 Aquantia / Atheros QCA / 其他 PHY 芯片改动
#           WH3000/WH3000 Pro (MT7981 Filogic) 使用 MediaTek 内置 PHY，
#           不依赖这些驱动，删除不影响设备功能。
# ════════════════════════════════════════════════════════════════
BKPORT_DIR="target/linux/generic/backport-6.6"
if [ -d "$BKPORT_DIR" ]; then
    COUNT=$(ls "$BKPORT_DIR"/7[0-9][0-9]-*.patch 2>/dev/null | wc -l)
    if [ "$COUNT" -gt 0 ]; then
        rm -f "$BKPORT_DIR"/7[0-9][0-9]-*.patch
        echo ">>> ✅ 已清理 700–799 段 backport-6.6 冲突 patches（共 $COUNT 个）"
    else
        echo ">>> ℹ️ 700–799 段 backport-6.6 无冲突 patch，跳过"
    fi
fi

# ════════════════════════════════════════════════════════════════
#  修复 gpio-button-hotplug 上游 API 兼容性
#
#  LEDE 上游更新使用了以下新内核 API：
#    1. devm_kmemdup_array              Linux ≥ 6.8  （6.6 需要 shim）
#    2. for_each_available_child_of_node_scoped  Linux ≥ 6.5（6.6 原生有，#ifndef 跳过）
#    3. void .remove 回调               Linux ≥ 6.11 （6.6 需要修改签名）
#
#  RE-SP-01B（Linux 5.10）已在 re-sp-01b.config 禁用该包，此 patch 对其无效
# ════════════════════════════════════════════════════════════════
GHBH_C="package/kernel/gpio-button-hotplug/src/gpio-button-hotplug.c"

if [ -f "$GHBH_C" ]; then
    echo ">>> 修复 gpio-button-hotplug 内核兼容性..."

    python3 << 'PYEOF'
import re

filepath = 'package/kernel/gpio-button-hotplug/src/gpio-button-hotplug.c'
with open(filepath, 'r') as f:
    content = f.read()

changed = False
shims = []

# ── Shim 1：devm_kmemdup_array（Linux >= 6.8，6.6 需要）────────
if 'devm_kmemdup_array' in content and '__compat_devm_kmemdup_array' not in content:
    shims.append(
        '/* COMPAT: devm_kmemdup_array (added Linux 6.8; #ifndef auto-skip on 6.8+) */\n'
        '#ifndef devm_kmemdup_array\n'
        '#include <linux/string.h>\n'
        'static inline void *__compat_devm_kmemdup_array(\n'
        '    struct device *dev, const void *src,\n'
        '    size_t n, size_t size, gfp_t gfp)\n'
        '{\n'
        '    void *p = devm_kmalloc_array(dev, n, size, gfp);\n'
        '    if (p) memcpy(p, src, n * size);\n'
        '    return p;\n'
        '}\n'
        '#define devm_kmemdup_array(dev, src, n, size, gfp) \\\n'
        '    __compat_devm_kmemdup_array(dev, src, n, size, gfp)\n'
        '#endif'
    )
    changed = True
    print('  OK: devm_kmemdup_array shim 已添加')

# ── Shim 2：for_each_available_child_of_node_scoped（Linux >= 6.5）──
# 6.6 原生有（#ifndef 自动跳过），保留 shim 以防万一
if ('for_each_available_child_of_node_scoped' in content and
        'compat_node_scoped' not in content):
    shims.append(
        '/* COMPAT: for_each_available_child_of_node_scoped (Linux >= 6.5)\n'
        ' * Linux 6.6 has this natively; #ifndef auto-skips this shim */\n'
        '#ifndef for_each_available_child_of_node_scoped\n'
        '#define for_each_available_child_of_node_scoped(parent, child) \\\n'
        '    for (struct device_node *(child) = \\\n'
        '             of_get_next_available_child((parent), NULL); \\\n'
        '         (child) != NULL; \\\n'
        '         (child) = of_get_next_available_child((parent), (child)))\n'
        '#endif'
    )
    changed = True
    print('  OK: for_each_available_child_of_node_scoped shim 已添加（6.6 自动跳过）')

# ── 插入 shims 到最后一个 #include 之后 ────────────────────────
if shims:
    combined = '\n\n' + '\n\n'.join(shims) + '\n\n'
    includes = list(re.finditer(r'^#include\s+.*$', content, re.MULTILINE))
    if includes:
        pos = includes[-1].end()
        content = content[:pos] + combined + content[pos:]
    else:
        content = combined + content

# ── Fix 3：void .remove → int .remove（Linux 6.11 才改为 void）──
lines = content.split('\n')
result = []
in_remove = False
depth = 0

for line in lines:
    if (not in_remove
            and 'static void ' in line
            and '_remove(' in line
            and 'platform_device' in line):
        line = line.replace('static void ', 'static int ', 1)
        in_remove = True
        depth = 0
        changed = True

    if in_remove:
        prev = depth
        depth += line.count('{') - line.count('}')
        if prev > 0 and depth == 0 and '}' in line:
            result.append('\treturn 0;')
            in_remove = False

    result.append(line)

content = '\n'.join(result)

if changed:
    with open(filepath, 'w') as f:
        f.write(content)
    print('  OK: gpio-button-hotplug 全部 patch 完成')
else:
    print('  INFO: 文件无需修复')
PYEOF

else
    echo ">>> gpio-button-hotplug 源文件不存在，跳过"
fi

echo "========================================"
echo " DIY Part 1 完成"
echo "========================================"
cat feeds.conf.default
