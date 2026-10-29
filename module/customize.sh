#!/system/bin/sh
# ─────────────────────────────────────────────────────────────
# customize.sh —— KSU/Magisk 安装期脚本
#
# 本版改动（相对上一版）：
#   1. 元模块缺失从 abort 改为警告，否则没装 magic_mount_rs 的
#      设备（例如部分 8G3 机型）在 KSU 里根本装不上。
#   2. 安装时记录「原厂 ro.hardware.vulkan」到状态目录，
#      卸载/切换按记录值还原，不再写死 adreno。
#   3. 安装一个 service.d 全局守护脚本，用于「模块被禁用」这种
#      不会执行 uninstall.sh 的场景下兜底还原属性 + 清缓存。
# ─────────────────────────────────────────────────────────────

SKIPUNZIP=0

STATE=/data/adb/turnip_enhanced

ui_print "- Turnip Enhanced (Mesa freedreno Vulkan)"

# ── 1. 设备兼容性检查 ─────────────────────────────────────────
if [ ! -e /dev/kgsl-3d0 ]; then
  ui_print "! 未找到 /dev/kgsl-3d0，此设备不是高通 kgsl 图形栈"
  ui_print "! Turnip 无法工作，安装中止"
  abort
fi

if [ "$ARCH" != "arm64" ]; then
  ui_print "! 本模块只有 arm64 产物，当前 ABI=$ARCH"
  abort
fi

ui_print "- 系统 API=$API"
# android-strict=false 编译，ANDROID_STRICT 宏未定义，
# vk_physical_device.c 的扩展白名单过滤整段不编译，
# 所以系统 API 高低不影响扩展可见性。此处只作记录。
if [ -n "$API" ] && [ "$API" -lt 34 ]; then
  ui_print "! API 偏低，loader/HWUI 行为可能与预期不同"
fi

# ── 2. 元模块检查（警告，不中止）──────────────────────────────
# 新版 KernelSU 下 overlay 挂载由元模块接管。没有元模块时
# system/vendor 可能不会被提升到 /vendor，但不同 KSU 版本/
# 不同元模块行为不一致，不能一概而论，所以这里只提示。
if [ -n "$KSU_VER_CODE" ] && [ "$KSU_VER_CODE" -ge 32179 ]; then
  if [ ! -d /data/adb/metamodule ]; then
    ui_print "! 未检测到元模块 /data/adb/metamodule"
    ui_print "! 若重启后 /vendor/lib64/hw/vulkan.turnip.so 不存在，"
    ui_print "! 请安装 magic_mount_rs 后重装本模块"
  else
    ui_print "- 元模块存在，挂载路径 OK"
  fi
fi

# ── 3. 冲突检查 ─────────────────────────────────────────────
for m in /data/adb/modules/*/; do
  id=$(basename "$m")
  [ "$id" = "turnip_enhanced" ] && continue
  if [ -f "$m/system/vendor/lib64/hw/vulkan.adreno.so" ] && \
     [ ! -f "$m/disable" ] && [ ! -f "$m/skip_mount" ]; then
    ui_print "! 检测到模块 $id 正在替换 vulkan.adreno.so"
    ui_print "! 与本模块（新增 vulkan.turnip.so + 改 ro.hardware.vulkan）冲突"
    ui_print "! 请先禁用 $id 再装本模块"
    abort
  fi
done

# ── 4. 恢复 system/vendor 布局 ───────────────────────────────
# 部分元模块（如 magic_mount_rs）会在调用本脚本前把
# $MODPATH/system/vendor 搬到顶层 $MODPATH/vendor，而它的挂载
# 扫描只认 <模块>/system，顶层 vendor 不会被挂。此处搬回来。
if [ -d "$MODPATH/vendor" ] && [ ! -d "$MODPATH/system/vendor" ]; then
  ui_print "- 恢复 system/vendor 布局（元模块把它搬到了顶层）"
  mkdir -p "$MODPATH/system"
  mv "$MODPATH/vendor" "$MODPATH/system/vendor"
fi
if [ -d "$MODPATH/product" ] && [ ! -d "$MODPATH/system/product" ]; then
  mkdir -p "$MODPATH/system"
  mv "$MODPATH/product" "$MODPATH/system/product"
fi
if [ -d "$MODPATH/system_ext" ] && [ ! -d "$MODPATH/system/system_ext" ]; then
  mkdir -p "$MODPATH/system"
  mv "$MODPATH/system_ext" "$MODPATH/system/system_ext"
fi

if [ ! -f "$MODPATH/system/vendor/lib64/hw/vulkan.turnip.so" ]; then
  ui_print "! 未找到 system/vendor/lib64/hw/vulkan.turnip.so"
  ui_print "! 模块目录结构异常，安装中止（避免装上一个不生效的模块）"
  abort
fi

# ── 5. 权限与 SELinux 上下文 ─────────────────────────────────
# 关键：目录和文件的 SELinux 类型必须分开设，不能一律 same_process_hal_file。
#
# 历史 bug：旧版把目录也打成 same_process_hal_file，导致非 root 应用
# 无法 search 目录 → dlopen("/vendor/lib64/hw/vulkan.turnip.so") 返回
# EACCES → Vulkan loader 认为 ICD 不存在 → 大部分应用判定「设备没有
# Vulkan」。root/shell 域对这些类型有 search 权限，所以只有普通应用
# 受影响，用 root 跑 vulkaninfo 一切正常，极具迷惑性。
#
# 正确基准（照抄本机原厂 /vendor 的标签）：
#   /vendor                     vendor_file
#   /vendor/lib64               vendor_file
#   /vendor/lib64/hw            vendor_hal_file
#   /vendor/etc                 vendor_configs_file
#   /vendor/etc/permissions     vendor_configs_file
#   *.so 文件                    same_process_hal_file
set_perm_recursive "$MODPATH/system" 0 0 0755 0644

for base in "$MODPATH/system/vendor" "$MODPATH/vendor"; do
  [ -d "$base" ] || continue
  ui_print "- 设置 SELinux 上下文: ${base#$MODPATH/}"
  set_perm_recursive "$base" 0 0 0755 0644
done

# ── 5a. 目录标签（按原厂基准逐级设置）────────────────────────
for root in "$MODPATH/system/vendor" "$MODPATH/vendor"; do
  [ -d "$root" ] || continue
  chcon u:object_r:vendor_file:s0         "$root"          2>/dev/null
  [ -d "$root/lib64" ]      && chcon u:object_r:vendor_file:s0      "$root/lib64"     2>/dev/null
  [ -d "$root/lib64/hw" ]   && chcon u:object_r:vendor_hal_file:s0  "$root/lib64/hw"  2>/dev/null
  [ -d "$root/lib" ]        && chcon u:object_r:vendor_file:s0      "$root/lib"       2>/dev/null
  [ -d "$root/lib/hw" ]     && chcon u:object_r:vendor_hal_file:s0  "$root/lib/hw"    2>/dev/null
  [ -d "$root/etc" ]        && chcon u:object_r:vendor_configs_file:s0 "$root/etc"      2>/dev/null
  [ -d "$root/etc/permissions" ] && chcon u:object_r:vendor_configs_file:s0 "$root/etc/permissions" 2>/dev/null
done

# ── 5b. 文件标签（.so 必须是 same_process_hal_file）──────────
# .so 文件本身用 same_process_hal_file，否则 vendor 库在 system 进程里
# 被 SELinux 拒 execute，dlopen 直接失败（avc denied execute）。
# 注意：这里只对「文件」设，不对目录设。
for root in "$MODPATH/system/vendor" "$MODPATH/vendor"; do
  [ -d "$root" ] || continue
  for d in "$root/lib64" "$root/lib64/hw" "$root/lib" "$root/lib/hw"; do
    [ -d "$d" ] || continue
    find "$d" -type f -exec chcon u:object_r:same_process_hal_file:s0 {} \; 2>/dev/null
  done
done

# 显式兜住两个主 .so（find 万一因路径异常漏掉时保险）
for so in "$MODPATH/system/vendor/lib64/hw/vulkan.turnip.so" \
          "$MODPATH/system/vendor/lib64/libc++_turnip.so"; do
  [ -f "$so" ] || continue
  set_perm "$so" 0 0 0644
  chcon u:object_r:same_process_hal_file:s0 "$so" 2>/dev/null
done

# ── 5c. /vendor/etc/permissions/*.xml 必须是 vendor_configs_file ──
for base in "$MODPATH/system/vendor/etc/permissions" "$MODPATH/vendor/etc/permissions"; do
  [ -d "$base" ] || continue
  set_perm_recursive "$base" 0 0 0755 0644 \
    u:object_r:vendor_configs_file:s0
  find "$base" -type f -name '*.xml' \
    -exec chcon u:object_r:vendor_configs_file:s0 {} \; 2>/dev/null
done

# ── 5d. 安装期自检：标签是否与原厂基准一致 ───────────────────
ui_print "- SELinux 标签自检："
for p in "$MODPATH/system/vendor:vendor_file" \
         "$MODPATH/system/vendor/lib64:vendor_file" \
         "$MODPATH/system/vendor/lib64/hw:vendor_hal_file" \
         "$MODPATH/system/vendor/etc/permissions:vendor_configs_file"; do
  path="${p%%:*}"; want="${p##*:}"
  [ -e "$path" ] || continue
  got=$(ls -dZ "$path" 2>/dev/null | awk '{print $1}' | sed 's/.*:\([a-z_]*\):s0/\1/')
  if [ "$got" = "$want" ]; then
    ui_print "    OK   ${path#$MODPATH/} = $got"
  else
    ui_print "    WARN ${path#$MODPATH/} = $got (期望 $want)"
  fi
done

# ── 6. 记录原厂属性值（关键）─────────────────────────────────
# 不再写死 adreno：不同机型原厂值可能是 adreno / adreno_v2 / 其它。
# 若本次安装前系统已经在跑 turnip（重装场景），则以历史记录为准。
mkdir -p "$STATE" 2>/dev/null
ORIG=$(getprop ro.hardware.vulkan)
if [ "$ORIG" = "turnip" ] || [ -z "$ORIG" ]; then
  if [ -f "$STATE/orig_vulkan" ]; then
    ORIG=$(cat "$STATE/orig_vulkan" 2>/dev/null)
  fi
fi
[ -z "$ORIG" ] && ORIG=adreno
echo "$ORIG" > "$STATE/orig_vulkan"
echo "turnip" > "$STATE/mode"
ui_print "- 原厂 ro.hardware.vulkan = $ORIG （已记录，卸载时按此还原）"

# ── 7. 安装全局守护脚本（禁用模块时的兜底）───────────────────
# 模块被「禁用」不会执行 uninstall.sh，属性可能停在 turnip，
# 而 vulkan.turnip.so 已经不可用 → loader 找不到驱动 → 黑屏。
# service.d 脚本与模块状态无关，每次开机都会执行。
if [ -d /data/adb/service.d ]; then
  cat > /data/adb/service.d/turnip_enhanced_guard.sh <<'GUARD'
#!/system/bin/sh
# Turnip Enhanced 兜底守护：每次开机执行，与模块启用状态无关。
# 若属性指向 turnip 但驱动文件不存在，说明模块已被禁用/移除，
# 必须把属性还原，否则 Vulkan loader 找不到驱动。
STATE=/data/adb/turnip_enhanced
RP=/data/adb/ksu/bin/resetprop
[ -x "$RP" ] || RP=resetprop

ORIG=$(cat "$STATE/orig_vulkan" 2>/dev/null)
[ -z "$ORIG" ] && ORIG=adreno
CUR=$(getprop ro.hardware.vulkan)

if [ "$CUR" = "turnip" ] && [ ! -f /vendor/lib64/hw/vulkan.turnip.so ]; then
  $RP ro.hardware.vulkan "$ORIG" 2>/dev/null
  # 换回原厂驱动后，turnip 生成的 shader/dalvik 缓存不兼容，
  # 不清会花屏或崩溃。
  rm -rf /data/vendor/gpu/*shader* 2>/dev/null
  rm -rf /data/vendor/gpu/*graphite* 2>/dev/null
  rm -rf /data/dalvik-cache/*/* 2>/dev/null
  rm -rf /data/system/package_cache/* 2>/dev/null
  echo "guard: turnip 驱动缺失，已还原 ro.hardware.vulkan=$ORIG 并清理缓存" \
    >> /sdcard/turnip_baseline/guard.log 2>/dev/null
fi
GUARD
  chmod 755 /data/adb/service.d/turnip_enhanced_guard.sh 2>/dev/null
  chcon u:object_r:system_file:s0 /data/adb/service.d/turnip_enhanced_guard.sh 2>/dev/null
  ui_print "- 已安装开机兜底脚本 service.d/turnip_enhanced_guard.sh"
fi

# ── 8. 备份快照 ──────────────────────────────────────────────
BASE=/sdcard/turnip_baseline
mkdir -p "$BASE" 2>/dev/null
{
  echo "# Turnip Enhanced 安装前快照 $(date '+%Y-%m-%d %H:%M:%S')"
  echo "ro.hardware.vulkan=$ORIG"
  echo "ro.board.platform=$(getprop ro.board.platform)"
  echo "ro.hwui.use_vulkan=$(getprop ro.hwui.use_vulkan)"
  echo "debug.hwui.renderer=$(getprop debug.hwui.renderer)"
  echo "# /vendor/lib64/hw/vulkan.adreno.so 未被本模块修改"
} > "$BASE/install-$(date +%Y%m%d-%H%M%S).txt" 2>/dev/null

ui_print "- 安装完成"
ui_print "- 重启后生效：ro.hardware.vulkan=turnip"
ui_print "- 切换驱动：管理器里点「执行」（action.sh，一次点击切换一次）"
ui_print "- 还原：卸载模块，或执行 $BASE/restore.sh"