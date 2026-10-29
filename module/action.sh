#!/system/bin/sh
# ─────────────────────────────────────────────────────────────
# action.sh —— 在 KSU 管理器里点「执行」时运行
#
# 上一版用 getevent 读音量键，在 KSU 里必然失败：
# /dev/input/event* 权限是 crw-rw---- root:input，action.sh 拿不到
# 按键事件，getevent 一直返回空，循环空转到超时，永远打印
# 「未检测到按键，未做修改」。所以本版改成「点一次切一次」，
# 读当前值取反，不再依赖任何按键。
# ─────────────────────────────────────────────────────────────

STATE=/data/adb/turnip_enhanced

RP=/data/adb/ksu/bin/resetprop
[ -x "$RP" ] || RP=resetprop

# ─────────────────────────────────────────────────────────────
# Vulkan 1.4 特性声明的开关
#
# 本机原厂 /vendor/etc/permissions 只有 version-1_1（4198400）和
# version-1_3（4206592），没有 1_4。模块自带一个 1_4.xml
# （4210688），让 PackageManager 报「本机支持 Vulkan 1.4」。
#
# 问题：模块的 overlay 一直挂着，不随 ro.hardware.vulkan 变化。
#   - 跑 turnip：报 1.4 正确（turnip 运行时 apiVersion 就是 1.4）
#   - 切回原厂：overlay 还在，PM 仍报 1.4，而 adreno 只有 1.3
#     → 应用 hasSystemFeature 拿到 1.4，按 1.4 建 instance 会崩
#
# 所以切回原厂时必须把这个 xml 停用。
#
# 为什么在 action.sh 而不是 post-fs-data.sh 做：
#   KSU 在 post-fs-data 阶段先跑 metamodule 的 metamount（建 overlay、
#   把模块目录复制进 ext4 镜像），再跑各模块的 post-fs-data.sh。
#   等我们的脚本运行时 overlay 已经挂好，改 lowerdir 影响不到合并
#   视图。而 action.sh 是切换时手动执行、随后必然重启，改的是模块
#   源目录，下次开机 metamount 重新复制时就会带上新状态。
#
# 实现：改名而不是删除，切回 turnip 时能原样恢复。
# 后缀 .disabled 不会被 PackageManager 当成 permission 文件加载。
# ─────────────────────────────────────────────────────────────
set_xml14() {
  # $1=1 启用 1.4 / $1=0 停用
  for P in \
    /data/adb/modules/turnip_enhanced/system/vendor/etc/permissions \
    /data/adb/modules/turnip_enhanced/vendor/etc/permissions
  do
    [ -d "$P" ] || continue
    X14="$P/android.hardware.vulkan.version-1_4.xml"
    XOFF="$P/android.hardware.vulkan.version-1_4.xml.disabled"
    if [ "$1" = "1" ]; then
      [ -f "$XOFF" ] && mv -f "$XOFF" "$X14" 2>/dev/null
    else
      [ -f "$X14" ] && mv -f "$X14" "$XOFF" 2>/dev/null
    fi
    [ -f "$X14" ] && chcon u:object_r:vendor_configs_file:s0 "$X14" 2>/dev/null
    [ -f "$XOFF" ] && chcon u:object_r:vendor_configs_file:s0 "$XOFF" 2>/dev/null
  done
}

ORIG=$(cat "$STATE/orig_vulkan" 2>/dev/null)
[ -z "$ORIG" ] && ORIG=adreno

CUR=$(getprop ro.hardware.vulkan)

echo "当前 Vulkan 驱动: $CUR"
case "$CUR" in
  turnip) echo "  → Turnip（Mesa 开源驱动）" ;;
  "$ORIG") echo "  → 原厂（$ORIG）" ;;
  *)      echo "  → 未知值" ;;
esac
echo

if [ "$CUR" = "turnip" ]; then
  # 切回原厂
  $RP ro.hardware.vulkan "$ORIG" 2>/dev/null
  echo "已切回原厂驱动：ro.hardware.vulkan=$ORIG"
  echo "$ORIG" > "$STATE/mode" 2>/dev/null
  # 原厂只有 1.3，必须停用模块的 1.4 声明，否则应用按 1.4 走会崩
  set_xml14 0
  echo "已停用 Vulkan 1.4 特性声明（原厂驱动只支持 1.3）"
  # 原厂驱动读不了 turnip 生成的 shader 缓存
  rm -rf /data/vendor/gpu/*shader* 2>/dev/null
  rm -rf /data/vendor/gpu/*graphite* 2>/dev/null
  echo "已清理 GPU shader 缓存（避免原厂驱动读到不兼容缓存）"
else
  # 切到 turnip
  if [ ! -f /vendor/lib64/hw/vulkan.turnip.so ]; then
    echo "! /vendor/lib64/hw/vulkan.turnip.so 不存在"
    echo "! 模块可能未正确挂载，无法切到 turnip"
    echo "! 请检查元模块是否安装，或重装本模块"
    sleep 8
    exit 1
  fi
  $RP ro.hardware.vulkan turnip 2>/dev/null
  echo "已切换到 Turnip：ro.hardware.vulkan=turnip"
  echo "turnip" > "$STATE/mode" 2>/dev/null
  # turnip 运行时 apiVersion 就是 1.4，恢复 1.4 声明
  set_xml14 1
  echo "已启用 Vulkan 1.4 特性声明"
  rm -rf /data/vendor/gpu/*shader* 2>/dev/null
  rm -rf /data/vendor/gpu/*graphite* 2>/dev/null
  echo "已清理 GPU shader 缓存"
fi

echo
echo "现在: $(getprop ro.hardware.vulkan)"
echo
echo "注意：已持有 Vulkan 句柄的进程（SystemUI、游戏等）"
echo "      需要重启才会换驱动。完整生效请重启设备。"
sleep 6