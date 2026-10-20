#!/system/bin/sh
# ─────────────────────────────────────────────────────────────
# uninstall.sh —— 模块被卸载时执行
# 照抄参考模块 adreno_gpu_driver 的清理清单（它的 uninstall.sh
# 还原成明文后就是清 shader / gpu cache / dalvik / resource cache）。
#
# 为什么必须清：换驱动后旧的 GPU shader 二进制缓存对新驱动可能
# 不兼容，会导致应用花屏或崩溃。清掉让系统重新编译。
# ─────────────────────────────────────────────────────────────

# 1. 立刻把属性切回原厂值（不等重启）
RP=/data/adb/ksu/bin/resetprop
[ -x "$RP" ] && $RP ro.hardware.vulkan adreno

# 2. 清 GPU 相关缓存
find /data/vendor/gpu -maxdepth 2 -type d \( -name '*shader*' -o -name '*graphite*' -o -name '*gpucache*' \) \
  -exec rm -rf {} + 2>/dev/null
rm -rf /data/vendor/gpu/qgl_config.txt 2>/dev/null

# 3. 清 dalvik / package / resource 缓存（系统会重建）
rm -rf /data/dalvik-cache/*/* 2>/dev/null
rm -rf /data/system/package_cache/* 2>/dev/null
rm -rf /data/resource-cache/* 2>/dev/null

# 4. 记录
echo "Turnip Enhanced 已卸载，ro.hardware.vulkan 已还原为 adreno" \
  >> /sdcard/turnip_baseline/uninstall.log 2>/dev/null

exit 0