# Turnip Enhanced

> 仓库：`oopnv70-lab/Turnip-Enhanced`　|　作者：**Operit**（oopnv70-lab，二改）
> 基于：[Mesa](https://gitlab.freedesktop.org/mesa/mesa) 的 freedreno / Turnip Vulkan 驱动，构建流程源自 [ilhan-athn7/freedreno_turnip-CI](https://github.com/ilhan-athn7/freedreno_turnip-CI)。

Mesa freedreno Vulkan 驱动 → KernelSU / Magisk 模块。
面向 **Adreno 8xx（本机 Adreno830v2 / a750 / pineapple）**，在 stock Mesa main 基础上做三件事：

1. **关掉 Android CTS 扩展白名单**（`-Dandroid-strict=false`），放出驱动已实现、但被 Android 白名单隐藏的扩展；
2. **补齐 Vulkan 1.4 feature xml**，让 PackageManager 认到 Vulkan 1.4；
3. **开启驱动已具备后端支持、但默认关闭的新扩展**（`VK_KHR_maintenance10`、`VK_KHR_shader_fma`）。

## 二改目标（相对上游的变更）
- 在 `ilhan-athn7/freedreno_turnip-CI` 构建脚本基础上改为**就地构建本仓库自带 Mesa 树**，不再外网下载 stock mesa；
- 关闭 `android-strict` 放出 21 个被白名单隐藏的 KHR 扩展；
- 模块内补 `android.hardware.vulkan.version-1_4.xml`；
- 在 `src/freedreno/vulkan/tu_device.cc` 中开启：
  - `VK_KHR_maintenance10`
  - `VK_KHR_shader_fma`（Float32/Float16，不含 Float64）
- 注：`VK_KHR_shader_bfloat16` 经调研**未开启**——ir3 后端不支持 bfloat16 相关 NIR opcode，强开会错误或崩溃。

---

## 一、与上游的差别

| # | 上游 | 本仓库 | 原因 |
|---|---|---|---|
| 1 | 无 `android-strict` 参数（默认 true） | `-Dandroid-strict=false` | 关掉 `ANDROID_STRICT` 宏，白名单过滤不参与编译 |
| 2 | `-Dplatform-sdk-version=34` | `=35` | 取 Mesa 默认值 |
| 3 | 无 1.4 feature xml | 新增 `android.hardware.vulkan.version-1_4.xml` | 本机 `/vendor/etc/permissions/` 无 1_4 |

> `-Dvulkan-beta=true` 上游有、本仓库也保留，但它只对 `vk.xml` 中标 `provisional="true"` 的扩展生效，Turnip 一个都没实现，实际是废开关。

---

## 二、能力确认

| 项 | 状态 |
|---|---|
| Vulkan 1.4 | 内建，无需改动（本机 chip=8） |
| 21 个隐藏扩展 | `android-strict=false` 放出 |
| 硬件光追 | 部分可用，完整 RT 管线不存在 |
| Cooperative Matrix / Pipeline Binary | 拿不到 |

被白名单隐藏、本仓库放出的 21 个：
`KHR_maintenance5` / `maintenance6` / `maintenance7` / `maintenance8` / `maintenance9`、
`KHR_shader_quad_control`、`KHR_shader_subgroup_rotate`、`KHR_shader_expect_assume`、
`KHR_shader_float_controls2`、`KHR_shader_relaxed_extended_instruction`、
`KHR_compute_shader_derivatives`、`KHR_dynamic_rendering_local_read`、
`KHR_index_type_uint8`、`KHR_line_rasterization`、`KHR_load_store_op_none`、
`KHR_map_memory2`、`KHR_vertex_attribute_divisor`、`KHR_depth_clamp_zero_one`、
`KHR_robustness2`、`KHR_unified_image_layouts`、`KHR_calibrated_timestamps`

---

## 三、模块结构

```
module/
├── module.prop
├── system.prop
├── customize.sh
├── action.sh
├── uninstall.sh
├── META-INF/com/google/android/
│   ├── update-binary
│   └── updater-script
└── system/vendor/
    ├── lib64/hw/vulkan.turnip.so
    └── etc/permissions/android.hardware.vulkan.version-1_4.xml
```

---

## 四、还原

**四层，从轻到重：**

1. **切回原厂驱动（不重启，只对新进程生效）**
   ```sh
   su -c "resetprop ro.hardware.vulkan adreno"
   ```
   已持有 Vulkan 句柄的进程需重启。
2. **禁用模块（重启后干净恢复）**
   ```sh
   su -c "touch /data/adb/modules/turnip_enhanced/disable"
   ```
   或管理器里关掉开关。
3. **一键脚本**
   ```sh
   su -c "sh /sdcard/turnip_baseline/restore.sh"
   ```
4. **彻底删除**
   ```sh
   su -c "rm -rf /data/adb/modules/turnip_enhanced && reboot"
   ```

`/vendor` 是 erofs 只读分区，本模块只**新增** `vulkan.turnip.so`，从不改写 `vulkan.adreno.so`。删模块重启即回原状，无需备份。

---

## 五、构建

GitHub Actions，手动触发（`workflow_dispatch`）。

| 参数 | 默认 | 说明 |
|---|---|---|
| `android_strict` | `false` | 想跑严格模式（对照组）时改 `true` |
| `platform_sdk` | `35` | Mesa 的 `-Dplatform-sdk-version` |

产物：`turnip-enhanced.zip`（KSU/Magisk 模块）。首次构建约 40–60 分钟。

---

## 六、风险

- `android-strict=false` 绕过 Android CTS 白名单，这是本项目的核心取舍。
- Turnip 是社区驱动，覆盖不如原厂 Adreno，**部分游戏可能反而不如原厂**。
- 光追拿不到完整管线。
- 临时 root 下重启后 root 失效，但模块由 KSU 自动加载；想无 root 还原请事先打 disable。

---

## 七、致谢

- [Mesa](https://gitlab.freedesktop.org/mesa/mesa) — freedreno / Turnip
- [ilhan-athn7/freedreno_turnip-CI](https://github.com/ilhan-athn7/freedreno_turnip-CI) — 构建脚本原型
- [LFRon/freedreno_turnip-stable](https://github.com/LFRon/freedreno_turnip-stable) — 稳定分支构建
- 二改作者：**Operit**（`oopnv70-lab/Turnip-Enhanced`）

---

## AI 声明

本仓库的部分调研、代码修改与文档内容由 AI 辅助生成。所有改动均经过人工确认与真机验证；如发现问题，请提交 Issue 反馈。
