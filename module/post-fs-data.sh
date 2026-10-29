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

# ─────────────────────────────────────────────────────────────
# 开机自愈：修正 overlay 目录的 SELinux 类型
#
# 背景：旧版 customize.sh 把目录也打成了 same_process_hal_file，
# 导致非 root 应用无法 search 目录，dlopen 拿 EACCES，Vulkan
# loader 判定 ICD 不存在。已在 customize.sh 修掉，但已安装的
# 用户不会重装，所以这里每次开机补一次。
#
# 只改目录类型，不碰文件（文件本来就该是 same_process_hal_file）。
# 全部静默失败，绝不影响开机。
# ─────────────────────────────────────────────────────────────
MP=/data/adb/modules/turnip_enhanced/system/vendor
if [ -d "$MP" ]; then
  chcon u:object_r:vendor_file:s0         "$MP"                  2>/dev/null
  [ -d "$MP/lib64" ]           && chcon u:object_r:vendor_file:s0      "$MP/lib64"          2>/dev/null
  [ -d "$MP/lib64/hw" ]        && chcon u:object_r:vendor_hal_file:s0  "$MP/lib64/hw"       2>/dev/null
  [ -d "$MP/lib" ]             && chcon u:object_r:vendor_file:s0      "$MP/lib"            2>/dev/null
  [ -d "$MP/lib/hw" ]          && chcon u:object_r:vendor_hal_file:s0  "$MP/lib/hw"         2>/dev/null
  [ -d "$MP/etc" ]             && chcon u:object_r:vendor_configs_file:s0 "$MP/etc"            2>/dev/null
  [ -d "$MP/etc/permissions" ] && chcon u:object_r:vendor_configs_file:s0 "$MP/etc/permissions" 2>/dev/null
fi
