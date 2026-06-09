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
#  清理 backport-6.6 冲突 patches（内容扫描，一次性彻底清理）
#
#  问题根因：LEDE 的 backport-6.6 目录里有一批 net/phy 驱动重组 patch，
#  将 at803x → qcom 子目录、aquantia → aquantia 子目录等。
#  这些 patch 之间存在依赖链：
#    702  → 创建 aquantia/ 目录
#    836  → 修改 aquantia/aquantia_main.c（依赖 702）
#    707  → 修改 at803x
#    713-01 → 创建 qcom/ 目录（at803x → qcom 重命名）
#    713-02 → 修改 qcom/ 内文件（依赖 713-01）
#    ...（未来可能还有更多）
#
#  之前按名称/编号删，每次只删一个，下一个 patch 又报错（打地鼠）。
#
#  正确做法：扫描 patch 文件内容，凡是涉及以下路径的一律删除：
#    drivers/net/phy/aquantia/   - Aquantia 驱动子目录
#    drivers/net/phy/qcom/       - Qualcomm QCOM 驱动子目录
#    net/phy/at803x              - Atheros at803x 驱动
#
#  安全性：WH3000/WH3000 Pro 使用 MT7981 MediaTek 内置 PHY，
#           完全不依赖 Aquantia / Qualcomm QCOM / Atheros at803x，
#           删除这些 patch 对设备功能无任何影响。
#           以后 LEDE 再新增相关 patch，也会被自动扫描并清理。
# ════════════════════════════════════════════════════════════════
BKPORT_DIR="target/linux/generic/backport-6.6"
if [ -d "$BKPORT_DIR" ]; then
    echo ">>> 扫描并清理 net/phy 冲突 patches..."
    REMOVED=0
    for f in "$BKPORT_DIR"/*.patch; do
        [ -f "$f" ] || continue
        # 检查 patch 内容是否涉及以下冲突 PHY 驱动路径
        if grep -qE \
            'drivers/net/phy/(aquantia|qcom)/|net/phy/at803x' \
            "$f" 2>/dev/null; then
            rm -f "$f"
            echo "  ✅ $(basename "$f")"
            REMOVED=$((REMOVED + 1))
        fi
    done
    if [ "$REMOVED" -eq 0 ]; then
        echo "  ℹ️ 未发现冲突 patch，无需清理"
    else
        echo "  ✅ 共清理 $REMOVED 个冲突 patch（内容扫描）"
    fi
fi

# ════════════════════════════════════════════════════════════════
#  修复 gpio-button-hotplug 上游 API 兼容性
#
#  LEDE 上游更新使用了以下新内核 API：
#    1. devm_kmemdup_array              Linux ≥ 6.8  （6.6 需要 shim）
#    2. for_each_available_child_of_node_scoped  Linux ≥ 6.5（6.6 原生有）
#    3. void .remove 回调               Linux ≥ 6.11 （6.6 需要修改签名）
#
#  均有 #ifndef 保护，内核原生支持时自动跳过
#  RE-SP-01B（Linux 5.10）已在 re-sp-01b.config 禁用该包
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
        '/* COMPAT: devm_kmemdup_array (added Linux 6.8; auto-skip on 6.8+) */\n'
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
if ('for_each_available_child_of_node_scoped' in content and
        'compat_node_scoped' not in content):
    shims.append(
        '/* COMPAT: for_each_available_child_of_node_scoped (Linux >= 6.5)\n'
        ' * Linux 6.6 has natively; #ifndef auto-skips */\n'
        '#ifndef for_each_available_child_of_node_scoped\n'
        '#define for_each_available_child_of_node_scoped(parent, child) \\\n'
        '    for (struct device_node *(child) = \\\n'
        '             of_get_next_available_child((parent), NULL); \\\n'
        '         (child) != NULL; \\\n'
        '         (child) = of_get_next_available_child((parent), (child)))\n'
        '#endif'
    )
    changed = True
    print('  OK: for_each_available_child_of_node_scoped shim 已添加')

# ── 插入 shims ──────────────────────────────────────────────────
if shims:
    combined = '\n\n' + '\n\n'.join(shims) + '\n\n'
    includes = list(re.finditer(r'^#include\s+.*$', content, re.MULTILINE))
    if includes:
        pos = includes[-1].end()
        content = content[:pos] + combined + content[pos:]
    else:
        content = combined + content

# ── Fix 3：void .remove → int .remove ──────────────────────────
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
