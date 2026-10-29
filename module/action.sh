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
# 关于 Vulkan 1.4 特性声明（android.hardware.vulkan.version-1_4.xml）
#
# 【已移除，勿再加回来】
# 本模块曾自带一个 version-1_4.xml（4210688），让 PackageManager 报
# 「本机支持 Vulkan 1.4」。这会导致 com.tencent.tmgp.dfm（UE4）启动即崩：
#
#   signal 11, fault addr 0x0, pc = 0
#   #01 libvulkan.so GetPhysicalDeviceSurfaceFormatsKHR+3500
#
# 机制：Turnip 的 TU_API_VERSION 是 1.4，加上该 xml 后应用确实会按 1.4
# 建 instance；而 Android 平台上 tu_wsi.cc 不参与编译
# （tu_wsi.h 里 TU_USE_WSI_PLATFORM 只对 x11/wayland/xlib/display 定义），
# 所以 pdevice->vk.wsi_device 始终为 NULL。一旦应用走 AHardwareBuffer
# 格式协商路径，loader 会间接调用 GetPhysicalDeviceSurfaceFormatsKHR，
# 该槽位为空 → blr x8 直接跳到地址 0。
#
# 上游 ilhan-athn7/freedreno_turnip-CI 的模块里**没有**这个 xml，
# 只放一个 vulkan.turnip.so，所以正常。本模块现在对齐上游：不带该 xml。
# 代价是 PM 只报到原厂 xml 的 1.3，属于预期行为。
# ─────────────────────────────────────────────────────────────

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