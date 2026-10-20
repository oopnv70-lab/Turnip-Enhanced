#!/system/bin/sh
# ─────────────────────────────────────────────────────────────
# action.sh —— 在 KSU 管理器里点「执行」时运行
# 照抄上游 turnip 模块的 action.sh 思路，但改成三段式菜单，
# 因为本机是「新增 vulkan.turnip.so」而非覆盖原厂文件，
# 切换只需要改属性，不需要动任何文件。
# ─────────────────────────────────────────────────────────────

RP=/data/adb/ksu/bin/resetprop
CUR=$(getprop ro.hardware.vulkan)

echo "当前 Vulkan 驱动: $CUR"
case "$CUR" in
  turnip) echo "  → 走 Turnip（Mesa 开源驱动）" ;;
  adreno) echo "  → 走 Adreno（高通原厂驱动）" ;;
  *)      echo "  → 未知值" ;;
esac
echo

echo "请选择（音量键）："
echo "  音量+  = 立即切到 Turnip"
echo "  音量-  = 立即切回 Adreno（原厂）"
echo

# 通过按键事件判断，最多等 10 秒
KEY=""
i=0
while [ $i -lt 20 ]; do
  EV=$(getevent -qlc 1 2>/dev/null | grep -m1 'KEY_VOLUME')
  case "$EV" in
    *KEY_VOLUMEUP*DOWN*)   KEY=up;   break ;;
    *KEY_VOLUMEDOWN*DOWN*) KEY=down; break ;;
  esac
  i=$((i+1))
done

case "$KEY" in
  up)
    $RP ro.hardware.vulkan turnip
    echo "已切换为 turnip。"
    echo "注意：已持有 Vulkan 句柄的进程（如 SystemUI、游戏）需要重启才会换驱动。"
    echo "完整生效请重启设备。"
    ;;
  down)
    $RP ro.hardware.vulkan adreno
    echo "已切回 adreno（原厂）。"
    echo "完整生效请重启设备。"
    ;;
  *)
    echo "未检测到按键，未做修改。"
    ;;
esac

echo
echo "当前: $(getprop ro.hardware.vulkan)"
sleep 5