# Turnip Enhanced

> 仓库：`oopnv70-lab/Turnip-Enhanced`　|　作者：**Operit**（oopnv70-lab，二改）
> 基于：[Mesa](https://gitlab.freedesktop.org/mesa/mesa) 的 freedreno / Turnip Vulkan 驱动，构建流程源自 [ilhan-athn7/freedreno_turnip-CI](https://github.com/ilhan-athn7/freedreno_turnip-CI)。

Mesa freedreno Vulkan 驱动 → KernelSU / Magisk 模块。
面向 **Adreno 8xx（本机 Adreno830v2 / a750 / pineapple）**，在 stock Mesa main 基础上做两件事：
1. **保持 Android CTS 扩展白名单开启**（`-Dandroid-strict=true`，即 Mesa 默认值，与上游一致）；
2. **开启驱动已具备后端支持、但默认关闭的新扩展**（`VK_KHR_maintenance10`、`VK_KHR_shader_fma`）。

> **重要历史教训（勿重犯）**：本项目曾改为 `-Dandroid-strict=false` 以「放开 21 个被白名单隐藏的扩展」，
> 结果游戏 `com.tencent.tmgp.dfm`（UE4）启动 2–4 秒即 SIGSEGV（pc=0，
> `libvulkan.so` 的 `GetPhysicalDeviceSurfaceFormatsKHR+3500`，x8 为 0 → `blr x8` 跳到地址 0）。
> 原因：关闭 `ANDROID_STRICT` 后 `VK_ANDROID_native_buffer` /
> `VK_ANDROID_external_memory_android_hardware_buffer` 等 AHardwareBuffer 相关扩展被声明为 supported，
> UE4 于是走 AHardwareBuffer 格式协商路径，间接调用 `GetPhysicalDeviceSurfaceFormatsKHR`；
> 而 Android 平台下 `tu_wsi.cc` 不参与编译（`TU_USE_WSI_PLATFORM` 未定义，见
> `src/freedreno/vulkan/meson.build` 的 `tu_wsi` 条件与 `tu_wsi.h:19`），
> `tu_wsi_init()` 整段被 `#ifdef` 掉，`physical_device->vk.wsi_device` 始终为 NULL，该函数槽位为空。
> 同理，模块内曾自带的 `android.hardware.vulkan.version-1_4.xml` 也已移除——它让 PackageManager
> 谎报本机支持 Vulkan 1.4（`version=4210688`），上游模块没有此文件，只放一个 `.so`。
## 二改目标（相对上游的变更）
- 在 `ilhan-athn7/freedreno_turnip-CI` 构建脚本基础上改为**就地构建本仓库自带 Mesa 树**，不再外网下载 stock mesa；
- `android-strict` 固定为 `true`（与上游一致，**不得改动**）；
- 模块内**不再**附带 `android.hardware.vulkan.version-1_4.xml`；
- 在 `src/freedreno/vulkan/tu_device.cc` 中开启：
  - `VK_KHR_maintenance10`
  - `VK_KHR_shader_fma`（Float32/Float16，不含 Float64）
- 注：`VK_KHR_shader_bfloat16` 经调研**未开启**——ir3 后端不支持 bfloat16 相关 NIR opcode，强开会错误或崩溃。
---
## 一、与上游的差别
| # | 上游 | 本仓库 | 原因 |
|---|---|---|---|
| 1 | 无 `android-strict` 参数（默认 true） | `-Dandroid-strict=true`（显式写死） | 与上游等价；关闭会触发 dfm 启动崩溃（见上） |
| 2 | `-Dplatform-sdk-version=34` | `=35` | 取 Mesa 默认值 |
| 3 | 只放一个 `.so` | 同样只放 `.so`，**不附带** 1.4 feature xml | 1.4 xml 会让 PackageManager 谎报 Vulkan 1.4 |
> `-Dvulkan-beta=true` 上游有、本仓库也保留，但它只对 `vk.xml` 中标 `provisional="true"` 的扩展生效，Turnip 一个都没实现，实际是废开关。
---
## 二、能力确认
| 项 | 状态 |
|---|---|
| Vulkan 1.4 | 内建，无需改动（本机 chip=8） |
| 被白名单隐藏的扩展 | **不放开**（`android-strict=true`），优先保证游戏不崩 |
| 硬件光追 | 部分可用，完整 RT 管线不存在 |
| Cooperative Matrix / Pipeline Binary | 拿不到 |

> 下列 21 个扩展曾被 `android-strict=false` 放开，但该设置会导致 dfm 启动崩溃，
> 现已**永久关闭**。保留清单仅作历史记录：
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
    └── lib64/hw/vulkan.turnip.so
```
> 上游 ilhan-athn7 的模块同样**只放一个 `.so`**，不带任何 `etc/permissions/*.xml`。本模块遵循该形态。

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
| `platform_sdk` | `35` | Mesa 的 `-Dplatform-sdk-version` |

> `android-strict` **不是可调参数**，已在 workflow `env` 中固定为 `true`。
> 构建后会校验 `meson configure` 的 `android-strict` 为 `true` 且 `build.ninja` 里含 `-DANDROID_STRICT`，否则 `exit 1`。
> 注意这两个宏来自 `pre_args`（编译命令行 `-D`），**不会写进 `config.h`**。

产物：`turnip-enhanced.zip`（KSU/Magisk 模块）。首次构建约 40–60 分钟。

---
## 安装前置要求
- 需要设备已获取 **Root 权限**；
- 需要安装 **KernelSU / Magisk** 或其他同类模块管理器；
- 安装与挂载须满足原模块 [ilhan-athn7/freedreno_turnip-CI](https://github.com/ilhan-athn7/freedreno_turnip-CI) 的前置要求，并按相同方式挂载。

## 设备兼容性声明
本仓库始于 **骁龙 8 至尊版（Adreno 830）**，但**不保证该平台所有设备均可使用**。

- 构建最初基于骁龙 8 至尊版（8 Elite）进行；
- 但已知测试设备没有永久性 root，依赖漏洞方式获取临时 root，漏洞稳定性极差；
- 安装本模块后，软重启会变成硬重启，进一步加重不稳定；
- 漏洞成功率极差，可能需要尝试二十多次、甚至几百次才能成功获取 root。

因此，目前仅确认以下设备**或许可能**运行：
- **骁龙 8 Gen 3 平台**（如一加 Ace5）

其他设备请自行测试，风险自负。

---
## 六、风险
- `android-strict` 曾设为 `false` 以绕过 Android CTS 白名单，**已证实会导致 dfm 启动崩溃，现固定为 `true`**。
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
