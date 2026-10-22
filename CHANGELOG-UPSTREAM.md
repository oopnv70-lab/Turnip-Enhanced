# Turnip Enhanced — 上游同步 Changelog

本文件记录本仓库 Mesa 树同步上游后，对 **Adreno / freedreno / Turnip (tu)** 实际可用的改动。
同步区间：Mesa main `2026-05-22` → `2026-10-22`（镜像源 `chaotic-cx/mesa-mirror`）。
共 9354 个上游提交；其中 `src/freedreno` 636 个，Turnip 直接相关 273 个。

以下只保留与我们设备（KGSL / a6xx / a7xx / a8xx，即 Adreno 6/7/8 系）有关的项。

---

## 一、功能与扩展

### Vulkan 扩展 / 版本
- **`VK_KHR_multiview` + Vulkan 1.3 在全部 a6xx 设备启用**（之前仅部分设备）
- 实现 **software multiview**（CPU draw 复制），老设备也能支持 multiview
- 实现 **`VK_QCOM_rotated_copy_commands`**
- 实现 **`VK_EXT_primitive_restart_index`**
- 实现 **SUBPASS_SLICE_FENCE flush**
- 广告 **`VK_KHR_shader_quad_control`**
- 广告 **`VK_EXT_shader_subgroup_ballot` / `VK_EXT_shader_subgroup_vote`**
- 支持 **`VALVE_buffer_device_address_allocation_alignment`**
- 广告 **`VK_KHR_internally_synchronized_queues`**（限 Vulkan 1.1+ 设备）
- 广告 **`VK_EXT_image_compression_control` / `_swapchain`**
- 支持 `subgroupQuadOperationsInAllStages`（能力允许时）
- 修复 `requiredSubgroupSizeStages` 的启用逻辑

### 设备支持新增
- **Adreno 829**（msm chip id）
- **Adreno 840（2-slice）**
- **Adreno 710 / 720**
- **Adreno X2-85、X1-45、722**
- **A702** 支持
- 启用 **A753 / A735**
- a8xx 派生性能计数器（perfcraw / ds）

### 应用专属 workaround / driconf
- **UE5 全量启用 SSBO 模拟**：`tu_enable_ssbo_emulation` 应用到所有 UE5 游戏（之前仅部分）
- **MGS4 强制 AMD vendor_id**
- **RDR2：DEVICE_LOCAL-only memory type**（新增 drirc 选项）
- **HL: Alyx（A750）：SP_CHICKEN_BITS_2 bit 30 workaround**
- **No Man's Sky：禁用 128-wide subgroups**
- **Clausewitz 引擎：`tu_allow_oob_indirect_ubo_loads`**
- **Kex Engine：`tu_dont_care_as_load` 全量启用**
- **skiavk（Android）：模拟第二 graphics queue**
- 支持 **`deviceName` 覆盖**（driconf）
- 支持 **`heap_memory_percent`**（driconf）
- 支持 **build ID 覆盖**
- **`TU_DEBUG=gmem_warmup`**：预分配大 VSC 给 GMEM 渲染
- **`TU_DEBUG=computeroundrobin`**
- **`TU_DEBUG=startup` 时打印 driconf 生效项**

### 上限调整
- 选项可调高 **最大 SSBO size** 与 **最大 texel buffer size**
- a8xx 设置 **真实 storage/texel buffer 上限**（不再用旧值）

---

## 二、Bug 修复（重点，按影响分类）

### KGSL 同步 / 等待 / 时间戳（10-08 集中修复）
- 修复 **BDA capture/replay 因延迟 VA 释放失败**
- 修复 **syncobj 泄漏** + 检查 suballoc 结果
- 修复 **wait-any 中 FD-only waits**
- 修复 **timestamps 与 sync files 合并错误**
- 修复 **queue_submit 中 syncobj 错误处理**
- 修复 **poll 结果解释错误**
- 修复 **wait-any 最早时间戳选择错误**
- 修复 **kgsl_syncobj_foreach_state OOB 数组访问**
- 修复 **0 timeout 无限等待**
- 修复 **wait timeout 未向上取整**
- 修复 **timestamp/sync wait 错误未区分**
- 修复 **kgsl_queue_wait_fence 溢出**
- 修复 **UBWC init 失败时 device/dma_fd 泄漏**
- 修复 **加载失败时 double-close**
- 修复 **内存类型支持检测**（不支持 flags 时）
- 初始化 dump bo state 提前，避免竞态

### 内存 / BO / 生命周期
- 修复 `kgsl_bo_init_dmabuf()` / `bo_init_new_ion_legacy()` / `tu_bo_map()` 错误处理
- 补充 `kgsl_bo_user_map()` 缺失的 `munmap()`
- 修复 perfcntr 分配错误处理
- 修复 `suballoc->bo` 错误路径未置 NULL
- 修复 FDM patch-points 内存泄漏
- 修复 submitqueue 创建失败时 vk_queue 泄漏
- 修复 descriptor set 分配碎片化失败时新 set 未释放
- 修复 pImmutableSamplers 处理错误（DescriptorSetLayoutSupport）
- 修复少数设备 mutex 泄漏
- 修复 **BO 命名被内核拒绝**、`tu_bo_set_kernel_name()` EINVAL

### 渲染正确性
- 修复 **texel buffer 模拟 bounds check**
- 修复 **bindless descriptor invalidate 序列**
- 修复 **push constant 范围收集提前退出**
- 修复 **ray queries 到非 uniform AS**
- 修复 **FDM 因 sample locations mismatch 丢图元**
- 修复 **sparse bind column merging**
- 修复 **inline uniform update offset**
- 修复 **GMEM_BASE GET_PARAM 失败信息**
- 修复 **LRZ 部分 render area clear 时错误复用**
- 修复 **LRZ 在 S/R 与 secondary 的 retroactive disable**
- 修复 **LRZ disabled_at_draw 信息**
- 修复 **custom resolve 的 LRZ 处理**
- 修复 **E5B9G9R9 MSAA clear 错误强制 R32_UINT**
- 修复 **R64 image clear 走非 generic 路径**
- 修复 **3D subresourceLayout.size 与 memcpy size**
- 修复 **gen8 TEX_LINE_OFFSET**
- 修复 **非 POT texel buffer 单 texel 对齐**
- 修复 **GPL（graphics pipeline library）set layouts 拼接**
- 修复 **VK_PIPELINE_CREATION_FEEDBACK cache hit bit**
- 修复 **speculatability 设置错误**
- 修复 **CmdWaitEvents2 的 pDependencyInfos 索引与 barrier 发射**
- 修复 **pipeline statistics query 的 vkResetQueryPool**
- 修复 **CmdBeginCustomResolveEXT 中的 resolves**
- 修复 **部分 subsampled 图像 renderpass**
- 修复 **FDM offset 下 GMEM clear（blit-event clear path）**
- 修复 **compiler options padding size**
- 修复 **`tu_event` 创建后未 reset**
- 修复 **multi-pass raw perf query（TU_DEBUG=perfcraw）**
- 修复 **subsampled metadata 与 separate stencil blit 发射**
- 修复 **TF counter READ_BIT 的 gfx_write_access 检查**
- 修复 **blit_cache_cleaned 未置 true**
- 修复 **maxFragmentInputComponents 上报**
- 修复 **D32S8 EARLY_Z_LATE_Z 挂起 workaround**
- 修复 **fragment shading rate sType**
- 修复 **A2R10G10B10 clear value pack**
- 修复 **tile division 算法**（tu/util）
- 修复 **GMEM layout 不可能时 gmem_offset 未初始化**

### 编译器 / ir3
- 修复 **load_const_ir3 base offset 潜在越界**
- 修复 **QCTDD13523866 workaround**
- 修复 **sched：kill 与 bary.f 不同 block 的调度错误**
- 修复 **16-bit SABS 求值**
- 修复 **source mod 对 denorm 的处理**（严格按硬件）
- 修复 **a7xx 上 aliasing texture 指令在 mova/(ul) 之间被调度**
- 新增 ir3_instr_prev/next helpers + lower_copies 校验
- 修复 mov_half_shared / alias_mova / alias_predication 等 quirks

### 其它
- 修复 **TU_CMD_DIRTY_DRAW_STATE 值冲突**
- 修复 **PACKED + alignas(8) 在旧 GCC 上的同一 struct 应用**
- 修复 **memory_budget_props->heapUsage 数据竞争**
- 修复 **renderpass tracepoints 在 s/r chains 丢失**
- 修复 **capture/replay sampler custom border color**
- 修复 **FDM extent compatibility 检查（tile_config）**
- 修复 **XFB counter offset 缩放（a6xx）**

---

## 三、优化 / 重构（提升性能或为后续铺路）

- **A8xx 拆分大型 indirect draws / indirect count draws**（大 draw call 稳定性 + 性能）
- **输入附件 lower 改用 texture 指令信息**
- **ir3 常量复用**（不同 src mods 复用已有 const）
- **shader cache 序列化/反序列化统一**（tu + ir3）
- **render pass state merge 提前到 draw cs merging 前**
- **移除 tu_sampler 引用（descriptor update template）**
- **subpass dependencies（EXTERNAL source）上移**
- **drm/tu 共享更多 msm 代码**（msm_common.h）
- **tu 与 freedreno/a6xx 拆分 VS driver params**
- **drirc 迁移到 drirc_gen**（tu + util）
- **a6xx 使用 a2d 做 z24s8 blits**

---

## 四、对用户的直观影响

1. **游戏兼容性**：
   - UE5 游戏（SSBO 模拟全量）→ 更多 UE5 游戏能跑/更稳
   - MGS4、RDR2、HL: Alyx、No Man's Sky、Kex 引擎游戏专项修复
2. **稳定性**：
   - KGSL 同步/等待/时间戳 13+ 修复，减少卡死、超时、崩溃
   - BO/内存生命周期 15+ 修复，减少泄漏导致的长时间游玩后性能下降或崩溃
3. **功能**：
   - Vulkan 1.3 在更多设备可用，新增多个扩展
   - 新设备 ID（829/840/710/720 等）识别
4. **性能**：
   - A8xx 大 draw 拆分
   - ir3 常量复用与调度修复
