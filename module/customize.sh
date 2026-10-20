#!/system/bin/sh
# ─────────────────────────────────────────────────────────────
# customize.sh —— KSU/Magisk 安装期脚本，由 install_module 调用
# 照抄 adreno_gpu_driver 的做法：给挂进 /vendor 的文件打正确的
# SELinux 上下文。缺了这一步，SELinux Enforcing 下 dlopen 会被拒。
# ─────────────────────────────────────────────────────────────

SKIPUNZIP=0

ui_print "- Turnip Enhanced (Mesa freedreno Vulkan)"

# ── 1. 设备兼容性检查 ─────────────────────────────────────────
# Turnip 的 kgsl 后端只支持高通 Adreno。本机 GPU 是 Adreno830v2
# （/sys/class/kgsl/kgsl-3d0/device/uevent 里是 qcom,adreno-gpu-gen8-0-1）。
if [ ! -e /dev/kgsl-3d0 ]; then
  ui_print "! 未找到 /dev/kgsl-3d0，此设备不是高通 kgsl 图形栈"
  ui_print "! Turnip 无法工作，安装中止"
  abort
fi

if [ "$ARCH" != "arm64" ]; then
  ui_print "! 本模块只有 arm64 产物，当前 ABI=$ARCH"
  abort
fi

# Android 版本提示。
# 注意：本模块构建时用了 -Dandroid-strict=false，ANDROID_STRICT 宏
# 不定义，vk_physical_device.c:96-99 那段扩展白名单过滤整段不编译，
# 所以 ALLOWED_ANDROID_VERSION 的 API 分档在这里完全不参与。
# 也就是说：系统 API 高低不会导致「白名单档位不匹配」，这个提示
# 只用于记录运气不好的老系统（那些系统的 loader 可能有别的限制）。
if [ -n "$API" ] && [ "$API" -lt 34 ]; then
  ui_print "! 系统 API=$API 偏低，loader/HWUI 行为可能与预期不同"
fi

# ── 2. 元模块检查 ────────────────────────────────────────────
# 参考模块在 KSU_VER_CODE>=32179 时强制要求 /data/adb/metamodule 存在，
# 因为新版 KSU 下 overlay 挂载由元模块接管，没有它 system/ 目录不会被
# 提升到 /vendor/。本机 ksud 3.3.0，该软链指向 magic_mount_rs，满足。
if [ -n "$KSU_VER_CODE" ] && [ "$KSU_VER_CODE" -ge 32179 ]; then
  if [ ! -d /data/adb/metamodule ]; then
    ui_print "! 检测到新版 KernelSU，但未安装元模块"
    ui_print "! 没有元模块，本模块的 system/vendor 不会被挂载到 /vendor"
    ui_print "! 请先安装 magic_mount_rs（或其它 metamodule）再装本模块"
    abort
  fi
  ui_print "- 元模块存在，挂载路径 OK"
fi

# ── 3. 冲突检查 ─────────────────────────────────────────────
# adreno_gpu_driver 会整体替换 /vendor/lib64/hw/vulkan.adreno.so。
# 两者同时启用时，谁后挂谁生效，行为不可预测，直接拦。
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

# ── 4. 关键修复：把被元模块搬走的 system/vendor 搬回来 ────────
# 这是照抄参考模块会直接踩的坑，必须有源码依据地说清楚：
#
# 本机 magic_mount_rs v4.0.11 的 metainstall.sh 第 37-48 行，
# 在调用 install_module（也就是执行本文件）之前就做了：
#     for part in vendor product system_ext; do
#       if [ -L "/system/$part" ] && [ -d "$MODPATH/system/$part" ]; then
#         mv "$MODPATH/system/$part" "$MODPATH/$part"
#       fi
#     done
# 本机 /system/vendor -> /vendor 是符号链接、/vendor 是独立分区，
# 两个条件都满足，所以 $MODPATH/system/vendor 此刻已经变成 $MODPATH/vendor。
#
# 但元模块挂载时的 collect_module_files()（magic_mount.rs:311）只遍历
#     entry.path().join("system")        ← 只认 <模块>/system
# 和 config.extra_mount（本机 config.toml 里是 []），
# 并且 config.rs:102 明确拒绝 /system 下已存在的分区名做 extra_mount。
# 也就是说：顶层 $MODPATH/vendor 这个目录，元模块**根本不会去挂**。
# 结果就是 has_mount_files=false → scan.ret 里 mode=ignore → 驱动不生效。
#
# metainstall.sh 尾部还有 mm_handle_partition()：它发现
# $MODPATH/system/vendor 存在时，才补一个 $MODPATH/vendor -> ./system/vendor
# 的符号链接。所以它的设计意图是「让 customize.sh 自己搬回来」。
# 这就是那段搬回逻辑的由来，不是多余动作。
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

# 自检：搬回来后必须能看到 so，否则宁可装失败也别装个不生效的
if [ ! -f "$MODPATH/system/vendor/lib64/hw/vulkan.turnip.so" ]; then
  ui_print "! 未找到 system/vendor/lib64/hw/vulkan.turnip.so"
  ui_print "! 模块目录结构异常，安装中止（避免装上一个不生效的模块）"
  abort
fi

# ── 5. 权限与 SELinux 上下文 ─────────────────────────────────
set_perm_recursive "$MODPATH/system" 0 0 0755 0644

for base in "$MODPATH/system/vendor" "$MODPATH/vendor"; do
  [ -d "$base" ] || continue
  ui_print "- 设置 SELinux 上下文: ${base#$MODPATH/}"
  # 目录 0755 / 文件 0644（set_perm_recursive 会递归设定）
  set_perm_recursive "$base" 0 0 0755 0644
done

# .so 必须 same_process_hal_file，否则 vendor 库在 system 进程里
# 被 SELinux 拒 execute，dlopen 直接失败（avc denied execute）。
for so in "$MODPATH/system/vendor/lib64/hw/vulkan.turnip.so"; do
  [ -f "$so" ] || continue
  set_perm "$so" 0 0 0644
  chcon u:object_r:same_process_hal_file:s0 "$so" 2>/dev/null
done
# lib64 目录本身及其它文件统一打上下文
for d in "$MODPATH/system/vendor/lib64" "$MODPATH/system/vendor/lib64/hw"; do
  [ -d "$d" ] || continue
  find "$d" -type f -exec chcon u:object_r:same_process_hal_file:s0 {} \; 2>/dev/null
  find "$d" -type d -exec chcon u:object_r:same_process_hal_file:s0 {} \; 2>/dev/null
done

# /vendor/etc/permissions/*.xml 必须是 vendor_configs_file，
# 否则 PackageManager 读不到 feature，Vulkan 1.4 不会被上报
for base in "$MODPATH/system/vendor/etc/permissions" "$MODPATH/vendor/etc/permissions"; do
  [ -d "$base" ] || continue
  set_perm_recursive "$base" 0 0 0755 0644 \
    u:object_r:vendor_configs_file:s0
  find "$base" -type f -name '*.xml' \
    -exec chcon u:object_r:vendor_configs_file:s0 {} \; 2>/dev/null
done

# ── 5. 备份当前属性到固定位置，便于一键还原 ──────────────────
BASE=/sdcard/turnip_baseline
mkdir -p "$BASE" 2>/dev/null
{
  echo "# Turnip Enhanced 安装前快照 $(date '+%Y-%m-%d %H:%M:%S')"
  echo "ro.hardware.vulkan=$(getprop ro.hardware.vulkan)"
  echo "ro.board.platform=$(getprop ro.board.platform)"
  echo "ro.hwui.use_vulkan=$(getprop ro.hwui.use_vulkan)"
  echo "debug.hwui.renderer=$(getprop debug.hwui.renderer)"
  echo "# 原厂驱动指纹（未被本模块修改，供核对）"
  echo "# /vendor/lib64/hw/vulkan.adreno.so 仍是只读分区原文件"
} > "$BASE/install-$(date +%Y%m%d-%H%M%S).txt" 2>/dev/null

ui_print "- 安装完成"
ui_print "- 重启后生效：ro.hardware.vulkan=turnip"
ui_print "- 还原：sh /sdcard/turnip_baseline/restore.sh"
ui_print "- 或在管理器里禁用本模块后重启"