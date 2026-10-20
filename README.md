# Turnip Enhanced

Mesa freedreno Vulkan 驱动 → KernelSU / Magisk 模块。

面向 **Adreno 8xx（本机 Adreno830v2 / a750 / pineapple）**，在 stock Mesa main 基础上关掉 Android CTS 扩展白名单，把驱动已经实现、但被 Android 白名单隐藏的扩展放出来。

---

## 一、与上游的差别（只有三处，其余照抄）

上游是 `ilhan-athn7/freedreno_turnip-CI` 的 `turnip_builder.sh`。本仓库的 `build-turnip.yml` 与它的参数差异仅此三点：

| # | 上游 | 本仓库 | 原因 |
|---|---|---|---|
| 1 | 无 `android-strict` 参数（默认 true） | `-Dandroid-strict=false` | 关掉 `ANDROID_STRICT` 宏，`vk_physical_device.c:96-99` 的白名单过滤整段不编译 |
| 2 | `-Dplatform-sdk-version=34` | `=35` | Mesa 默认档位，见下方说明 |
| 3 | 无 1.4 feature xml | 新增 `android.hardware.vulkan.version-1_4.xml` | 本机 `/vendor/etc/permissions/` 只有 1_1 和 1_3，无 1_4 |

`-Dvulkan-beta=true` 上游有、本仓库**也保留**，但要知道它是废开关：`vk_extensions.py:213` 里它只对 `vk.xml` 中标 `provisional="true"` 的扩展生效，而 provisional 全表只有 5 个（`VK_AMDX_shader_enqueue`、`VK_KHR_portability_subset`、`VK_NV_cuda_kernel_launch`、`VK_NV_displacement_micromap`、`VK_AMDX_dense_geometry_format`），Turnip 一个都没实现。留着无害，别指望它。

---

## 二、关于 `android-strict` 与 `platform-sdk-version` 的关系（重要，容易搞混）

这两个不是叠加关系，是**互斥的两条路**。

`src/vulkan/runtime/vk_physical_device.c`：

```c
for (int i = 0; i < VK_DEVICE_EXTENSION_COUNT; i++) {
   if (!pdevice->supported_extensions.extensions[i])
      continue;
#ifdef ANDROID_STRICT
   if (!vk_android_allowed_device_extensions.extensions[i])
      continue;
#endif
   ...
```

- **路径 A：`android-strict=true`（默认）** — 白名单生效。此时提高 `platform-sdk-version` 才有意义，因为白名单表 `ALLOWED_ANDROID_VERSION`（`vk_extensions.py:248`）按 API 分档，实测 141 条、分成 26/27/28/29/30/31/33/34/35/36/37 十一档（36 档 6 条、37 档 10 条）。改档位能多放几条。
- **路径 B：`android-strict=false`（本仓库走这条）** — `ANDROID_STRICT` 宏不定义，整个 `if` 连同白名单表**根本不参与**。这时 `platform-sdk-version` 调多高都无所谓。

所以本仓库 `SDKVER=35` 只是取 Mesa 默认值，不是因为 35 有什么特殊好处。

### 顺便纠正一个常见误解

NDK 的 `platforms.json` 写的是 `"max": 35`，**NDK r29 也一样**。也就是说 `aarch64-linux-android36-clang` 这类 wrapper 根本不存在。`platform-sdk-version` 和 NDK 的 API 是两件不同的事，混用会直接编译失败。本仓库用两个独立变量 `SDKVER` 与 `NDK_API` 分开，就是为了避免这个坑。

---

## 三、确认能拿到的能力

| 项 | 状态 | 依据 |
|---|---|---|
| Vulkan 1.4 | **内建，无需改动** | `tu_device.cc:137` `TU_API_VERSION = VK_MAKE_VERSION(1,4,...)`；第 1332 行 `chip >= 7` 走 1.4，本机 chip=8 |
| 21 个隐藏扩展 | **`android-strict=false` 放出** | 见下方清单 |
| 硬件光追 | **部分可用，完整 RT 管线不存在** | 见下方说明 |
| Cooperative Matrix | **拿不到** | `KHR_cooperative_matrix` 在 `tu_device.cc` 中 0 命中 |
| Pipeline Binary | **拿不到** | 同上，0 命中 |

### 被 sdk=34 白名单隐藏、本仓库放出的 21 个

`KHR_maintenance5` / `maintenance6` / `maintenance7` / `maintenance8` / `maintenance9`、
`KHR_shader_quad_control`、`KHR_shader_subgroup_rotate`、`KHR_shader_expect_assume`、
`KHR_shader_float_controls2`、`KHR_shader_relaxed_extended_instruction`、
`KHR_compute_shader_derivatives`、`KHR_dynamic_rendering_local_read`、
`KHR_index_type_uint8`、`KHR_line_rasterization`、`KHR_load_store_op_none`、
`KHR_map_memory2`、`KHR_vertex_attribute_divisor`、`KHR_depth_clamp_zero_one`、
`KHR_robustness2`、`KHR_unified_image_layouts`、`KHR_calibrated_timestamps`

> 注：`EXT_` / `QCOM_` / `VALVE_` 前缀的扩展在 `vk_extensions.py:52-55` 里直接 `return 'true'`，本来就不受白名单限制，不在上表内。上表统计的是 `ANDROID_EXTENSION_WHITELIST_PREFIXES = ("VK_KHX","VK_KHR","VK_GOOGLE","VK_ANDROID")` 里被档位卡住的部分。

### 光追的真实边界（不要抱错觉）

硬件层面 a750 有光追单元（`freedreno_devices.py` 里 `a7xx_gen3` 设 `has_ray_intersection=True`），但：

```c
// tu_device.cc:225
bool has_raytracing = device->info->props.has_ray_intersection &&
                      (!device->info->props.has_sw_fuse || device->has_raytracing);
```

`device->has_raytracing` 来自 `tu_knl_kgsl.cc:2014` → `tu_kgsl_get_raytracing()` → `get_kgsl_prop(fd, KGSL_PROP_IS_RAYTRACING_ENABLED)`（`msm_kgsl.h:358`，值 `0x2D`）。**这是内核报告的硅片熔丝值，纯用户态改不了**，任何编译开关都绕不过。

结果是：
- `KHR_acceleration_structure`、`KHR_ray_query`、`KHR_ray_tracing_maintenance1` — 存在，但受上面熔丝门控
- `KHR_ray_tracing_pipeline` — **源码里 0 命中，完整 RT 管线不存在**

自证方法：`vulkaninfo` 里 GPU 名若带 `" (raytracing disabled)"` 后缀（`tu_device.cc:2194`），就是熔丝关闭。

---

## 四、模块形态与挂载

```
module/
├── module.prop
├── system.prop                                  # 属性
├── customize.sh                                 # 安装期：权限/上下文/布局修复
├── action.sh                                    # 管理器里点执行：turnip ⇄ adreno 切换
├── uninstall.sh                                 # 卸载：还原属性 + 清 GPU/dalvik 缓存
├── META-INF/com/google/android/
│   ├── update-binary                            # 仅 Magisk/recovery 路径用到
│   └── updater-script
└── system/vendor/
    ├── lib64/hw/vulkan.turnip.so                # CI 产出后填入
    └── etc/permissions/android.hardware.vulkan.version-1_4.xml
```

### 为什么写 `system/vendor/` 而不是 `vendor/`

本机装的是元模块 `magic_mount_rs` v4.0.11。它的 `magic_mount.rs:376-390` 会把 `<模块>/system/{vendor,system_ext,product}` 提升到根分区，条件是 `/system/X` 是符号链接。本机 `/system/vendor -> /vendor` 满足，所以模块内照常写 `system/vendor/`。

### 但有一个真实陷阱（照抄会踩）

`metainstall.sh` 第 37-48 行，在调用 `install_module`（也就是执行 `customize.sh`）**之前**就干了这事：

```sh
for part in vendor product system_ext; do
  if [ -L "/system/$part" ] && [ -d "$MODPATH/system/$part" ]; then
    mv "$MODPATH/system/$part" "$MODPATH/$part"
  fi
done
```

于是 `customize.sh` 执行时，`$MODPATH/system/vendor` 已经变成 `$MODPATH/vendor` 了。

而元模块挂载时的 `collect_module_files()`（`magic_mount.rs:353`）**只遍历 `<模块>/system`**，加上 `config.extra_mount`（本机是 `[]`）—— 顶层 `vendor/` 它根本不看。`config.rs:102` 还明确拒绝把 `/system` 下已存在的名字当 `extra_mount`。

后果：`has_mount_files=false` → `scan.ret` 里 `mode=ignore` → 模块装了完全没效果，而且**不报错**。

所以 `customize.sh` 第 62-98 行有一段搬回逻辑，把 `vendor/` 移回 `system/vendor/`。这不是多余动作，`metainstall.sh` 尾部的 `mm_handle_partition()` 就是给这段留的钩子（它在 `system/vendor` 存在时才补 `vendor -> ./system/vendor` 软链）。

已在真机复现并验证修复：

```
模拟 metainstall 搬运 → moved system/vendor -> vendor
执行搬回逻辑        → ./system/vendor/etc/permissions/...
                     → ./system/vendor/lib64/hw                   ✓
```

### 属性时序

KernelSU 3.3.0 的 `init_event.rs:on_post_fs_data()` 顺序是：

```
101  metamodule post-fs-data script
106  modules post-fs-data script
110  load_system_prop()          ← system.prop 在这里生效
116  exec_mount_script()         ← 元模块在这里挂文件
```

两者都在 post-fs-data 内、zygote 启动之前，先后顺序不影响结果。所以用 `system.prop` 是安全的，不必改用 `resetprop`。

---

## 五、还原

**四层，从轻到重：**

1. **切回原厂驱动（不重启即刻生效，但只对新进程有效）**
   ```
   su -c "/data/adb/ksu/bin/resetprop ro.hardware.vulkan adreno"
   ```
   注意：已经持有 Vulkan 句柄的进程（SystemUI、游戏）不会自动切，要重启。

2. **禁用模块（重启后干净恢复）**
   ```
   su -c "touch /data/adb/modules/turnip_enhanced/disable"
   ```
   或管理器里关掉开关。文件保留，可随时启用。

3. **一键脚本**
   ```
   su -c "sh /sdcard/turnip_baseline/restore.sh"
   ```
   做三件事：还原属性 + 打 disable/skip_mount + 清 GPU 缓存。

4. **彻底删除**
   ```
   su -c "rm -rf /data/adb/modules/turnip_enhanced && reboot"
   ```

**为什么不需要备份原厂驱动：** `/vendor` 是 erofs 只读分区，本模块只**新增** `vulkan.turnip.so`，从不改写 `vulkan.adreno.so`。overlay/bind mount 只「盖住」不「改写」，删模块重启即回到原状。原厂文件指纹仍有记录，供核对：

```
/vendor/lib64/hw/vulkan.adreno.so   5,350,592 B
sha256 ec11a136f13113970252a6877a9a732b45de08f77530cd6d1c197121935c8e7d
md5    520a65a58770507868327eb1007e1150
```

**「原有扩展怎么还原」的答案是：没有可还原的对象。** 扩展列表是编译期产物，编进 `.so` 里。换回原厂 `.so` 就回到原厂扩展集，没有中间态、没有运行时开关。

---

## 六、装机前检查清单

- [ ] 已卸载 / 禁用 `adreno_gpu_driver`（它替换 `vulkan.adreno.so`，与本质变更 `ro.hardware.vulkan` 冲突，两个同时启用行为不可预测）
- [ ] `/data/adb/metamodule` 存在（本机指向 `magic_mount_rs`）
- [ ] 有 `vulkaninfo` 之类的工具能验扩展（本机目前**没有**，见下）
- [ ] 知道怎么救：记住 `resetprop ro.hardware.vulkan adreno`

### 验扩展的工具缺口

本机没有 `vulkaninfo`、没有 dEQP，`dumpsys gpu` 只给 `vkLoadingCount / vkLoadingFailureCount`，不列扩展。

可行方案：装 **VulkanCapsViewer**（`de.saschawillems.vulkancapsviewer`），直接看 `apiVersion` 是否 1.4、扩展列表是否包含上面 21 个。

### 装完怎么判断成功

```
getprop ro.hardware.vulkan          # 应为 turnip
ls /vendor/lib64/hw/                # 应能看到 vulkan.turnip.so
dumpsys gpu | grep -i vulkan        # vkLoadingFailureCount 应为 0/不增
```

如果 `vkLoadingFailureCount` 涨了，或出现黑屏/花屏，直接走还原路径 2 或 3，然后重启。

---

## 七、构建

GitHub Actions，手动触发（`workflow_dispatch`），参数：

| 参数 | 默认 | 说明 |
|---|---|---|
| `mesa_ref` | `main` | Mesa 分支/标签 |
| `android_strict` | `false` | 想跑严格模式（做对照组）时改 `true` |
| `platform_sdk` | `35` | Mesa 的 `-Dplatform-sdk-version` |

产物（artifact，保留 30 天）：
- `turnip-enhanced.zip` — KSU/Magisk 模块
- `turnip-adrenotools.zip` — 模拟器 / `libadrenotools` 用

首次构建约 40–60 分钟（Mesa 全量编译 + thin LTO）。

---

## 八、风险

- `android-strict=false` 绕过 Android CTS 白名单。理论上某些应用会因为看到「未认证扩展」而行为异常。这是本项目的核心取舍。
- Turnip 是社区驱动，功能覆盖不如原厂 Adreno 驱动，**部分游戏可能反而不如原厂**。本项目给的是可回退的另一条路，不是「一定更好」。
- 光追拿不到完整管线，别指望开光追游戏。
- 临时 root 环境下，重启后 root 失效，但模块由 KSU 在 late-load 阶段自动加载，属性照样生效。想在无 root 状态下还原，走路径 2（前提是你事先已经 `touch` 了 disable）。

---

## 九、致谢

- [Mesa](https://gitlab.freedesktop.org/mesa/mesa) — freedreno / Turnip
- [ilhan-athn7/freedreno_turnip-CI](https://github.com/ilhan-athn7/freedreno_turnip-CI) — 构建脚本原型
- [LFRon/freedreno_turnip-stable](https://github.com/LFRon/freedreno_turnip-stable) — 稳定分支构建
- [Tools-cx-app/meta-magic_mount-rs](https://github.com/Tools-cx-app/meta-magic_mount-rs) — 元模块
