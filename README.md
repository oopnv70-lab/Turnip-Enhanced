# Turnip Enhanced

Mesa 的 freedreno / Turnip Vulkan 驱动，打包为 KernelSU / Magisk 模块。

面向高通 Adreno GPU 的 Android 设备，替换系统 Vulkan 驱动。

---

## 一、血缘关系：这不是上游

本项目**不是上游**，处在链条的第四层。每一层的职责不同：

```
① Mesa 官方
   gitlab.freedesktop.org/mesa/mesa
   freedreno / Turnip 驱动的原始实现
        │
        ├──② chaotic-cx/mesa-mirror
        │     GitHub 上的 Mesa 镜像，本项目曾用它作为 rebase 基线
        │
        └──② ilhan-athn7/freedreno_turnip-CI
              构建流程的原型：把 Mesa 交叉编译成 Android 可用的 .so，
              并打包成 KernelSU / Magisk 模块
                   │
                   ③ LFRon/Turnip-Enhanced
                   本项目的直接上游。在 Mesa 基础上叠加了骁龙平台的
                   兼容性与布局修复，本仓库的结构直接派生自它
                        │
                        ④ oopnv70-lab/Turnip-Enhanced  ← 本项目
                          在上游之上做本地化取舍
```

**关键点：本项目的 `main` 是 `LFRon/Turnip-Enhanced` 的 fork**（GitHub 的 `parent` 字段可查）。所以“上游”这个词在本仓库里指 LFRon，不是 Mesa。

### 上游代码 vs 本项目改动

仓库的 git 历史里混着三种来源，看 `git log` 时要注意区分：

| 来源 | commit 数 | 说明 |
|---|---|---|
| Mesa 社区 | 1800+ | 完整继承自上游，含 `Marge Bot` 的合并记录 |
| LFRon | 92 | 直接上游的修复，整体搬运，未做改动 |
| 本项目 | 72 | 自己的提交，全部集中在建仓之后 |

**继承来的提交保持原 SHA 不变**，说明是整体搬运而不是 rebase 重写。查某条提交是谁写的，看 `author` 字段即可；LFRon 有两个显示名（`LFRon` 与 `mozixun`），是同一人。

---

## 二、依赖的项目

| 项目 | 用途 | 关系 |
|---|---|---|
| [Mesa](https://gitlab.freedesktop.org/mesa/mesa) | freedreno / Turnip Vulkan 驱动的原始实现 | 代码来源，本仓库自身即一份 Mesa 树（`VERSION` = `27.0.0-devel`） |
| [chaotic-cx/mesa-mirror](https://github.com/chaotic-cx/mesa-mirror) | Mesa 的 GitHub 镜像 | 曾作为 2026-10-22 的 rebase 基线，用于比对上游修复 |
| [ilhan-athn7/freedreno_turnip-CI](https://github.com/ilhan-athn7/freedreno_turnip-CI) | 交叉编译 + 模块打包流程 | 构建脚本原型；本项目的模块形态与它一致 |
| [LFRon/Turnip-Enhanced](https://github.com/LFRon/Turnip-Enhanced) | 直接上游 | 本仓库 fork 自它，Mesa 树通过它同步 |
| [LFRon/freedreno_turnip-stable](https://github.com/LFRon/freedreno_turnip-stable) | 同一作者的稳定分支 | 参考对象 |
| Android NDK | 交叉编译工具链 | `aarch64-linux-android35-clang` |
| Meson / Ninja | 构建系统 | Mesa 原生构建方式 |
| KernelSU / Magisk | 模块加载 | 产物运行环境 |

---

## 三、哪部分是本项目写的

**72 条自有提交**，全部由两个 git 身份产生（同一人）：

| 身份 | 条数 |
|---|---|
| `operit` | 37 |
| `oopnv70-lab` | 32 |
| `oopnv70-lab`（noreply 变体） | 3 |

按改动领域分布：

| 前缀 | 条数 | 内容 |
|---|---|---|
| `ci` | 22 | 构建流程、产物发布、上游同步工作流 |
| `tu` | 11 | Turnip 驱动行为（扩展开关等） |
| `freedreno/tu` | 4 | TLS 段 64 字节对齐（Bionic 加载器要求） |
| `sync` / `util` | 7 | 从上游搬运代码 |
| `docs` | 6 | 文档 |
| `module` / `fix(module)` | 5 | SELinux 标签、驱动切换、模块自愈 |
| 其他 | 17 | 仓库初始化、chore、revert 等 |

### 关于 AI 参与

`AGENTS.md` 要求 AI 参与的提交带 `Assisted-by: LLM` 尾注。实际情况：

- **22 条带标注**
- **50 条不带**

所以“哪些是 AI 写的”这个问题，**无法用尾注完整区分**——早期约定尚未落实时提交的改动没有标注。

细看这 22 条，AI 参与的部分集中在两类：

1. **调查与文档**（runbook、同步 changelog、构建流程重写）
2. **驱动行为的具体判断**（如 `VK_EXT_external_memory_host` 的启停裁定）

而**模块打包、SELinux 标签、TLS 对齐、CI 缓存这些确定性的工程改动，多数是人工完成**。

### 本项目真正原创的部分

绝大部分代码来自上游。本项目真正做的事只有三类：

1. **构建与打包** —— 把 Mesa 树就地编译成 Android 模块，不下载外网 archive
2. **针对本机平台的取舍** —— 开关哪些扩展、保留哪些行为
3. **真机验证** —— 每一项改动都在 Adreno 830 上实测，崩溃与修复都有 logcat 记录可查

---

## 许可证

本仓库继承 Mesa 的许可结构，`licenses/` 目录下包含：

`Apache-2.0`、`BSL-1.0`、`GPL-1.0-or-later`、`GPL-2.0-only`、`MIT`、`SGI-B-2.0`

Mesa 采用**按文件划分**的多许可证方式，具体文件适用哪个许可证见文件头声明与 `licenses/` 目录。上游与本项目均未在 GitHub 上声明单一 SPDX 许可证，改为沿用 Mesa 原有的许可结构。
