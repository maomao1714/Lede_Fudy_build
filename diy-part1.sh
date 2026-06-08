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
#  修复 gpio-button-hotplug 上游兼容性问题
#
#  LEDE 上游更新该包，使用了以下新内核 API：
#    1. devm_kmemdup_array              Linux ≥ 6.8   我们：5.10 / 6.6
#    2. for_each_available_child_of_node_scoped  Linux ≥ 6.5  我们：5.10
#    3. void .remove 回调              Linux ≥ 6.11  5.10/6.6 需返回 int
#
#  修法：编译前自动 patch 源文件，添加兼容层（均有 #ifndef 保护）
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
if 'devm_kmemdup_array' in content and '__compat_devm_kmemdup_array' not in content:
    shims.append(
        '/* COMPAT: devm_kmemdup_array was added in Linux 6.8 */\n'
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
    print('  OK: devm_kmemdup_array 兼容层已添加')

# ── Shim 2：for_each_available_child_of_node_scoped（Linux >= 6.5）──
# 该宏在 6.5 引入，支持 C 变量作用域自动清理
# 5.10 没有此宏，用 C99 for 循环声明变量替代
if ('for_each_available_child_of_node_scoped' in content and
        'compat_node_scoped' not in content):
    shims.append(
        '/* COMPAT: for_each_available_child_of_node_scoped (Linux >= 6.5) */\n'
        '/* Fallback using C99 for-loop variable declaration */\n'
        '#ifndef for_each_available_child_of_node_scoped\n'
        '#define for_each_available_child_of_node_scoped(parent, child) \\\n'
        '    for (struct device_node *(child) = \\\n'
        '             of_get_next_available_child((parent), NULL); \\\n'
        '         (child) != NULL; \\\n'
        '         (child) = of_get_next_available_child((parent), (child)))\n'
        '#endif'
    )
    changed = True
    print('  OK: for_each_available_child_of_node_scoped 兼容层已添加')

# ── 将所有 shim 统一插入到最后一个 #include 之后 ──────────────
if shims:
    combined = '\n\n' + '\n\n'.join(shims) + '\n\n'
    includes = list(re.finditer(r'^#include\s+.*$', content, re.MULTILINE))
    if includes:
        pos = includes[-1].end()
        content = content[:pos] + combined + content[pos:]
    else:
        content = combined + content

# ── Fix 3：void .remove → int .remove（Linux >= 6.11 改为 void）──
# 5.10 / 6.6 的 platform_driver.remove 仍需返回 int
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
        # 检测函数体最外层闭合花括号，在其前插入 return 0
        if prev > 0 and depth == 0 and '}' in line:
            result.append('\treturn 0;')
            in_remove = False

    result.append(line)

content = '\n'.join(result)

if changed:
    with open(filepath, 'w') as f:
        f.write(content)
    print('  OK: gpio-button-hotplug patch 完成')
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
