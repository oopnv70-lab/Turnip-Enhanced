#!/system/bin/sh
# ─────────────────────────────────────────────────────────────
# post-fs-data.sh —— 开机早期执行（/data 已挂载，zygote 未启动）
#
# 作用：按状态文件决定本次开机用哪个 Vulkan 驱动。
#
# 默认由 system.prop 写 ro.hardware.vulkan=turnip；本脚本只在
# 用户通过 action.sh 切回原厂时才覆盖。这样即使本脚本因为任何
# 原因没跑起来，默认行为仍然是「用 turnip」，不会变成不可用状态。
# ─────────────────────────────────────────────────────────────

STATE=/data/adb/turnip_enhanced

RP=/data/adb/ksu/bin/resetprop
[ -x "$RP" ] || RP=resetprop

MODE=$(cat "$STATE/mode" 2>/dev/null)
ORIG=$(cat "$STATE/orig_vulkan" 2>/dev/null)
[ -z "$ORIG" ] && ORIG=adreno

if [ "$MODE" = "adreno" ] || [ "$MODE" = "orig" ]; then
  # 用户选择原厂驱动
  $RP ro.hardware.vulkan "$ORIG" 2>/dev/null
else
  # 默认：turnip
  $RP ro.hardware.vulkan turnip 2>/dev/null
fi
