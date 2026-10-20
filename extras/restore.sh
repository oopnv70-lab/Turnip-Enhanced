#!/system/bin/sh
# ─────────────────────────────────────────────────────────────
# restore.sh —— 一键把设备恢复到「原厂 Adreno 驱动」状态
#
# 用法（需要 root）：
#   su -c "sh /sdcard/turnip_baseline/restore.sh"
#
# 它做三件事，对应三层还原：
#   1. 属性层：ro.hardware.vulkan 改回 adreno
#   2. 文件层：/vendor 是 erofs 只读分区，原厂文件从未被改动，
#              Turnip 只是新增了 vulkan.turnip.so 并被 bind mount
#              盖住 —— 禁用模块后重启，原厂状态自动回来
#   3. 模块层：给模块目录打 disable 标记
#
# 这个脚本不需要、也不会写入任何分区。
# ─────────────────────────────────────────────────────────────

RP=/data/adb/ksu/bin/resetprop
MODID=turnip_enhanced
MODDIR=/data/adb/modules/$MODID

echo "=== Turnip Enhanced 还原 ==="
echo

# ── 1. 属性还原 ──────────────────────────────────────────────
echo "[1/3] 还原 ro.hardware.vulkan"
if [ -x "$RP" ]; then
  OLD=$(getprop ro.hardware.vulkan)
  $RP ro.hardware.vulkan adreno
  echo "      $OLD -> $(getprop ro.hardware.vulkan)"
else
  echo "      ! 找不到 $RP（可能已失去 root）"
  echo "      ! 属性未能还原，需要手动 root 后执行："
  echo "        resetprop ro.hardware.vulkan adreno"
fi

# 清掉可能存在的 debug.hwui.renderer 覆盖
if [ -x "$RP" ]; then
  $RP -d debug.hwui.renderer 2>/dev/null
  echo "      debug.hwui.renderer 已删除（回到系统默认）"
fi
echo

# ── 2. 模块禁用 ──────────────────────────────────────────────
echo "[2/3] 禁用模块"
if [ -d "$MODDIR" ]; then
  touch "$MODDIR/disable"
  touch "$MODDIR/skip_mount"
  echo "      已写入 $MODDIR/disable 和 skip_mount"
  echo "      模块文件和配置会保留，可随时重新启用"
else
  echo "      模块目录不存在，跳过"
fi
echo

# ── 3. 清 GPU 缓存（可选但建议）───────────────────────────────
echo "[3/3] 清理 GPU 缓存"
find /data/vendor/gpu -maxdepth 2 -type d \
  \( -name '*shader*' -o -name '*graphite*' -o -name '*gpucache*' \) \
  -exec rm -rf {} + 2>/dev/null
find /data/dalvik-cache -maxdepth 2 -type f -name '*shader*' -delete 2>/dev/null
rm -rf /data/resource-cache/* 2>/dev/null
echo "      完成"
echo

echo "=== 还原完成，请重启设备 ==="
echo
echo "重启后验证："
echo "  getprop ro.hardware.vulkan     # 应为 adreno"
echo "  ls /vendor/lib64/hw/           # 不会看到 vulkan.turnip.so"
echo
echo "如果重启后仍异常，说明 /vendor 里还有残留 bind mount："
echo "  再重启一次通常能清掉（bind mount 不跨重启）"
echo
echo "要彻底删除模块（而非仅禁用）："
echo "  su -c 'rm -rf /data/adb/modules/$MODID && reboot'"
echo "或直接在 KSU 管理器里点卸载。"