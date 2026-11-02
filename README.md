# Turnip Enhanced

> 仓库：`oopnv70-lab/Turnip-Enhanced`　|　作者：**Operit**（oopnv70-lab，二改）
> 基于：[Mesa](https://gitlab.freedesktop.org/mesa/mesa) 的 freedreno / Turnip Vulkan 驱动，构建流程源自 [ilhan-athn7/freedreno_turnip-CI](https://github.com/ilhan-athn7/freedreno_turnip-CI)。

Mesa freedreno Vulkan 驱动 → KernelSU / Magisk 模块。

## 一、能力确认
| 项 | 状态 |
|---|---|
| Vulkan 1.4 | 内建，无需改动（本机 chip=8） |
| 硬件光追 | 部分可用，完整 RT 管线不存在 |
| Cooperative Matrix / Pipeline Binary | 拿不到 |


---

## 二、模块结构

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

## 三、还原

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

## 四、构建

GitHub Actions，手动触发（`workflow_dispatch`）。

| 参数 | 默认 | 说明 |
|---|---|---|
| `platform_sdk` | `35` | Mesa 的 `-Dplatform-sdk-version` |


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
## 五、风险
- Turnip 是社区驱动，覆盖不如原厂 Adreno，**部分游戏可能反而不如原厂**。
- 光追拿不到完整管线。
- 临时 root 下重启后 root 失效，但模块由 KSU 自动加载；想无 root 还原请事先打 disable。

---

## 六、致谢

- [Mesa](https://gitlab.freedesktop.org/mesa/mesa) — freedreno / Turnip
- [ilhan-athn7/freedreno_turnip-CI](https://github.com/ilhan-athn7/freedreno_turnip-CI) — 构建脚本原型
- [LFRon/freedreno_turnip-stable](https://github.com/LFRon/freedreno_turnip-stable) — 稳定分支构建
- 二改作者：**Operit**（`oopnv70-lab/Turnip-Enhanced`）

---

## AI 声明

本仓库的部分调研、代码修改与文档内容由 AI 辅助生成。所有改动均经过人工确认与真机验证；如发现问题，请提交 Issue 反馈。
