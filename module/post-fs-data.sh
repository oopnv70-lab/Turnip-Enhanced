#!/system/bin/sh
# ─────────────────────────────────────────────────────────────
# post-fs-data.sh —— 开机早期执行（/data 已挂载，zygote 未启动）
#
# 作用一：按状态文件决定本次开机用哪个 Vulkan 驱动。
# 作用二：给 overlay 源文件补 SELinux 标签（开机自愈）。
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
# 开机自愈：给 vulkan.turnip.so 补 SELinux 标签
#
# 根因（真机实测确认，Android 16 / ColorOS）：
#   /vendor/etc/selinux/vendor_file_contexts 只给
#     vulkan.adreno.so / vulkan.lahaina.so / vulkan.mali.so.tango
#   显式打了 same_process_hal_file，没有 vulkan.turnip.so。
#   于是它落到 plat_file_contexts 的兜底规则：
#     /(vendor|system/vendor)(/.*)?  ->  vendor_file
#   而 plat_sepolicy.cil 里：
#     (allow domain vendor_file (dir (getattr search)))     ← 目录能进
#     (allow appdomain same_process_hal_file (file (...)))  ← 只有这个
#     grep -c 'allow appdomain vendor_file' = 0             ← 文件打不开
#   结果：普通应用 dlopen 在 open() 就被 EACCES 拦死，Vulkan loader
#   判定 ICD 不存在。root/su 域有 vendor_file 权限，所以 root 跑
#   vulkaninfo 正常 —— 这就是这个 bug 只在非 root 应用暴露的原因。
#
# 两条独立防线：
#   防线 1（本脚本）：把源文件的标签改成 same_process_hal_file。
#                    overlayfs 会把 lower inode 的 security.* xattr
#                    透传到合并视图，所以改 lowerdir 源文件即可。
#   防线 2（sepolicy.rule）：万一 overlay/ext4 复制丢了 xattr、标签
#                    退回 vendor_file，ksud 应用的那条 allow 仍然
#                    让普通应用能读能 map。不依赖 xattr 是否保住。
#
# 注意两点（上一版的错误）：
#   1. 必须改「文件」，不能只改目录。
#   2. 路径不能写死 /data/adb/modules/...。metamodule 用
#      overlay_mode=ext4 时会复制一份到自己的 mnt 下，那份才是
#      overlay 的 lowerdir。所以这里用 find 动态定位所有副本。
# ─────────────────────────────────────────────────────────────

# 给一个 vendor 树打标签：目录按原厂基准，.so 一律 same_process_hal_file
fix_tree() {
  d="$1"
  [ -d "$d" ] || return 0

  # 目录：照抄原厂 /vendor 的标签
  chcon u:object_r:vendor_file:s0         "$d"            2>/dev/null
  [ -d "$d/lib64" ]           && chcon u:object_r:vendor_file:s0         "$d/lib64"           2>/dev/null
  [ -d "$d/lib64/hw" ]        && chcon u:object_r:vendor_hal_file:s0     "$d/lib64/hw"        2>/dev/null
  [ -d "$d/lib" ]             && chcon u:object_r:vendor_file:s0         "$d/lib"             2>/dev/null
  [ -d "$d/lib/hw" ]          && chcon u:object_r:vendor_hal_file:s0     "$d/lib/hw"          2>/dev/null
  [ -d "$d/etc" ]             && chcon u:object_r:vendor_configs_file:s0 "$d/etc"             2>/dev/null
  [ -d "$d/etc/permissions" ] && chcon u:object_r:vendor_configs_file:s0 "$d/etc/permissions" 2>/dev/null

  # 文件：关键修复。分开判断目录存在性，避免 toybox find 对
  # 不存在的路径报错后跳过其余参数。
  if [ -d "$d/lib64" ]; then
    find "$d/lib64" -type f -name '*.so' \
      -exec chcon u:object_r:same_process_hal_file:s0 {} \; 2>/dev/null
  fi
  if [ -d "$d/lib" ]; then
    find "$d/lib" -type f -name '*.so' \
      -exec chcon u:object_r:same_process_hal_file:s0 {} \; 2>/dev/null
  fi
}

# 逐个候选根目录处理（存在哪个就修哪个，全都不存在也不报错）
for MP in \
  /data/adb/metamodule/mnt/turnip_enhanced/vendor \
  /data/adb/metamodule/mnt/turnip_enhanced/system/vendor \
  /data/adb/modules/turnip_enhanced/vendor \
  /data/adb/modules/turnip_enhanced/system/vendor
do
  fix_tree "$MP"
done

# 模块自带的 /system/lib64/libc++_turnip.so 副本（不在 vendor 树下）
for L in \
  /data/adb/metamodule/mnt/turnip_enhanced/system/lib64 \
  /data/adb/modules/turnip_enhanced/system/lib64
do
  [ -d "$L" ] || continue
  chcon u:object_r:system_lib_file:s0 "$L" 2>/dev/null
  find "$L" -type f -name '*.so' \
    -exec chcon u:object_r:same_process_hal_file:s0 {} \; 2>/dev/null
done

# 兜底：万一上面路径全没命中（未来 metamodule 改布局），
# 直接在 /data/adb 下限定深度搜这两个文件，连同父目录一起修。
# 注意两点：
#   1. 只处理 vendor 树下的文件。system/lib64 那份 libc++_turnip.so
#      属于 /system，原厂基准是 system_lib_file，不能按 vendor 打。
#   2. 父目录要按目录名判断类型，不能一律 vendor_hal_file：
#        .../hw  -> vendor_hal_file（原厂 /vendor/lib64/hw 就是这个）
#        其它     -> vendor_file（原厂 /vendor、/vendor/lib64 都是这个）
#      上一版一律打 vendor_hal_file，会把 /vendor/lib64 标错。
for f in $(find /data/adb -maxdepth 8 \
             \( -name 'vulkan.turnip.so' -o -name 'libc++_turnip.so' \) \
             2>/dev/null); do
  case "$f" in
    */vendor/*) : ;;
    *) continue ;;
  esac
  chcon u:object_r:same_process_hal_file:s0 "$f" 2>/dev/null
  pd=$(dirname "$f")
  case "$(basename "$pd")" in
    hw) chcon u:object_r:vendor_hal_file:s0 "$pd" 2>/dev/null ;;
    *)  chcon u:object_r:vendor_file:s0     "$pd" 2>/dev/null ;;
  esac
done

# 最后尝试直接修合并视图（/vendor 只读时大概率失败，静默忽略）。
# 有些 metamodule 配置下 lowerdir 不可写，但合并路径可 chcon。
if [ -e /vendor/lib64/hw/vulkan.turnip.so ]; then
  chcon u:object_r:same_process_hal_file:s0 /vendor/lib64/hw/vulkan.turnip.so 2>/dev/null
  chcon u:object_r:same_process_hal_file:s0 /vendor/lib64/libc++_turnip.so 2>/dev/null
fi