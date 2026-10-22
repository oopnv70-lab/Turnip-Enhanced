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