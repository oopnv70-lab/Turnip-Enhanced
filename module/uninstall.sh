#!/system/bin/sh
# ─────────────────────────────────────────────────────────────
# uninstall.sh —— 模块被卸载时执行
#
# 关键点：卸载不会自动重启，属性必须立刻还原，否则当前这次
# 开机里 Vulkan loader 还会去找已经不存在的 vulkan.turnip.so。
#
# 还原值来自安装时记录的 /data/adb/turnip_enhanced/orig_vulkan，
# 不再写死 adreno（不同机型原厂值不同）。
# ─────────────────────────────────────────────────────────────

STATE=/data/adb/turnip_enhanced

RP=/data/adb/ksu/bin/resetprop
[ -x "$RP" ] || RP=resetprop

# 1. 立刻把属性切回原厂值
ORIG=$(cat "$STATE/orig_vulkan" 2>/dev/null)
[ -z "$ORIG" ] && ORIG=adreno
$RP ro.hardware.vulkan "$ORIG" 2>/dev/null
echo "uninstall: ro.hardware.vulkan -> $ORIG"

# 2. 清 GPU 相关缓存
# 换驱动后旧的 GPU shader 二进制缓存对新驱动不兼容，
# 会导致应用花屏或崩溃，必须清掉让系统重新编译。
find /data/vendor/gpu -maxdepth 2 -type d \
  \( -name '*shader*' -o -name '*graphite*' -o -name '*gpucache*' \) \
  -exec rm -rf {} + 2>/dev/null
rm -rf /data/vendor/gpu/qgl_config.txt 2>/dev/null

# 3. 清 dalvik / package / resource 缓存（系统会重建）
rm -rf /data/dalvik-cache/*/* 2>/dev/null
rm -rf /data/system/package_cache/* 2>/dev/null
rm -rf /data/resource-cache/* 2>/dev/null

# 4. 移除开机兜底脚本（模块已卸载，不再需要）
rm -f /data/adb/service.d/turnip_enhanced_guard.sh 2>/dev/null

# 5. 保留 orig_vulkan 记录，方便重装时正确识别原厂值
#    （若原厂值本身就是 adreno，重装时 getprop 会读到 adreno，
#     逻辑同样正确，所以这里只删 mode）

rm -f "$STATE/mode" 2>/dev/null

# 6. 记录
echo "Turnip Enhanced 已卸载，ro.hardware.vulkan 已还原为 $ORIG" \
  >> /sdcard/turnip_baseline/uninstall.log 2>/dev/null

exit 0