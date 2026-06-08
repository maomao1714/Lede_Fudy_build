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
#  修复 aquantia PHY backport patch 冲突
#
#  根因：Linux 6.6.142 已将 aquantia PHY 驱动原生移入子目录
#        (drivers/net/phy/aquantia/)，但 LEDE 的 backport patch 仍
#        尝试重复创建这些文件，导致 toolchain/kernel-headers 编译失败
#  修法：删除冲突的 backport patch 文件，内核中已有原生实现
#  影响：仅 Linux 6.6 构建（WH3000/WH3000 Pro），5.x 构建不受影响
# ════════════════════════════════════════════════════════════════
BKPORT_DIR="target/linux/generic/backport-6.6"
if [ -d "$BKPORT_DIR" ]; then
    echo ">>> 检查 aquantia backport patch 冲突..."
    REMOVED=0
    for f in "$BKPORT_DIR"/70[0-9]-*aquantia*.patch; do
        if [ -f "$f" ]; then
            rm -f "$f"
            echo "  ✅ 已移除冲突 patch：$(basename "$f")"
            REMOVED=$((REMOVED + 1))
        fi
    done
    if [ "$REMOVED" -eq 0 ]; then
        echo "  ℹ️ 未发现 aquantia 冲突 patch，跳过"
    else
        echo "  ✅ aquantia patch 冲突已清除（共 $REMOVED 个）"
    fi
fi

# ════════════════════════════════════════════════════════════════
#  修复 gpio-button-hotplug 上游 API 兼容性
#
#  LEDE 上游更新使用了以下新内核 API：
#    1. devm_kmemdup_array              Linux ≥ 6.8
#    2. for_each_available_child_of_node_scoped  Linux ≥ 6.5
#    3. void .remove 回调               Linux ≥ 6.11
#
#  兼容策略（用 #ifndef 保护，符合要求的内核自动跳过 shim）：
#    - API 2：Linux 6.6 原生有（6.5 引入），#ifndef 自动跳过 shim
#    - API 1：Linux 6.6 没有（6.8 引入），shim 生效
#    - API 3：Linux 6.6 没有（6.11 引入），直接修改函数签名
#    - RE-SP-01B（Linux 5.10）：config 已禁用该包，不会编译，此 patch 对其无效
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

# ── Shim 1：devm_kmemdup_array（Linux >= 6.8）──────────────────
# Linux 6.6 没有此函数（6.8 才有），shim 生效
# Linux 6.8+ 有原生实现，#ifndef 自动跳过
if 'devm_kmemdup_array' in content and '__compat_devm_kmemdup_array' not in content:
    shims.append(
        '/* COMPAT: devm_kmemdup_array (added in Linux 6.8)\n'
        ' * Linux 6.8+: #ifndef skips this shim automatically */\n'
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
    print('  OK: devm_kmemdup_array shim 已添加（6.6 生效，6.8+ 自动跳过）')

# ── Shim 2：for_each_available_child_of_node_scoped（Linux >= 6.5）──
# Linux 6.6 原生有此宏（6.5 引入），#ifndef 自动跳过此 shim
# 此 shim 仅为 < 6.5 内核准备（当前 6.6 构建不会执行）
if ('for_each_available_child_of_node_scoped' in content and
        'compat_node_scoped' not in content):
    shims.append(
        '/* COMPAT: for_each_available_child_of_node_scoped (added in Linux 6.5)\n'
        ' * Linux 6.5+: #ifndef skips this shim automatically\n'
        ' * Linux 6.6 has this natively - this shim is inactive */\n'
        '#ifndef for_each_available_child_of_node_scoped\n'
        '#define for_each_available_child_of_node_scoped(parent, child) \\\n'
        '    for (struct device_node *(child) = \\\n'
        '             of_get_next_available_child((parent), NULL); \\\n'
        '         (child) != NULL; \\\n'
        '         (child) = of_get_next_available_child((parent), (child)))\n'
        '#endif'
    )
    changed = True
    print('  OK: for_each_available_child_of_node_scoped shim 已添加（6.6 原生有，自动跳过）')

# ── 将 shim 插入到最后一个 #include 之后 ──────────────────────
if shims:
    combined = '\n\n' + '\n\n'.join(shims) + '\n\n'
    includes = list(re.finditer(r'^#include\s+.*$', content, re.MULTILINE))
    if includes:
        pos = includes[-1].end()
        content = content[:pos] + combined + content[pos:]
    else:
        content = combined + content

# ── Fix 3：void .remove → int .remove ──────────────────────────
# platform_driver.remove 在 Linux 6.11 改为 void
# Linux 6.6 仍使用 int，直接修改函数签名
# 使用 brace-depth 计数在函数末尾插入 return 0
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
    print('  OK: gpio-button-hotplug 全部兼容 patch 完成')
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
