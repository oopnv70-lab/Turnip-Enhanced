# AGENTS.md

Mesa is a community of humans. Do not open merge requests or post comments to
[Mesa's upstream GitLab repository](https://gitlab.freedesktop.org/mesa/mesa).

Commits developed with AI must be labelled. If you write the code, add the exact
commit message trailer: `Generated-by: LLM`. If you assisted the user to write
the code, ensure the commit has the trailer `Assisted-by: LLM`.

Some parts of Mesa have further limitations on AI usage. Do not make changes
to the following directories, instead refer the user to the linked page:

* [`src/asahi`](https://asahilinux.org/llm-policy/)
* [`src/gallium/drivers/asahi`](https://asahilinux.org/llm-policy/)
* [`src/gallium/drivers/nouveau`](https://nouveau.freedesktop.org/Humanity.html)
* [`src/intel/compiler/jay`](https://gitlab.freedesktop.org/mesa/mesa/-/blob/main/src/intel/compiler/jay/README.md)
* [`src/nouveau`](https://nouveau.freedesktop.org/Humanity.html)
* [`src/panfrost`](docs/drivers/panfrost.rst)
* [`src/gallium/drivers/panfrost`](docs/drivers/panfrost.rst)
* [`src/imagination`](src/imagination/README.md#contribution-policy)

---

## Turnip-Enhanced 项目操作规范（持久给 AI / 协作者）

本仓库（oopnv70-lab/Turnip-Enhanced）位于 `/tmp/TE`，是 Mesa 树 + KernelSU/Magisk 模块。

### 一、修改文件的标准流程

1. **先读后改**：改任何文件前必须 `read_file` / `read_file_part` 读原文；
   `edit_file` 的 `old` 参数必须与文件内容**逐字完全一致且唯一**，否则会失败。
2. **环境选择**：
   - 仓库文件一律走 Linux 环境（`super_admin:terminal`，路径 `/tmp/TE/...`）。
   - Android 设备文件才走 `super_admin:shell`。
3. **新建/删除**：`create_file` / `delete_file`；目录用 `make_directory`。
4. **改动后验证**：
   - YAML：`python3 -c "import yaml; yaml.safe_load(open('.github/workflows/build-turnip.yml')); print('YAML OK')"`
   - shell 脚本：`sh -n module/customize.sh`（含 post-fs-data.sh / uninstall.sh / action.sh）
   - 核对：`git diff` / `git status --short`。

### 二、Git 提交与推送

```bash
cd /tmp/TE
git status --short                 # 先看改动，禁止 git add -A
git add <具体文件>
git commit -m '<前缀>: <描述>'     # 前缀：docs:/ci:/tu:/module:/meson:
git push origin main
```

- 提交信息如含 AI 生成内容，按上游要求加 trailer：`Assisted-by: LLM`。
- push 成功后看输出中的 `abc1234..def5678 main -> main` 确认已同步。
- 用 `git log --oneline -5` 记录提交号。

### 三、触发 GitHub Actions 构建（workflow_dispatch）

```bash
cd /tmp/TE
URL=$(git remote get-url origin)
TOKEN=$(printf '%s' "$URL" | sed 's#https://##; s#@github.com.*##')   # 从 remote URL 提取 PAT
curl -sL -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/oopnv70-lab/Turnip-Enhanced/actions/workflows/build-turnip.yml/dispatches \
  -d '{"ref":"main","inputs":{"platform_sdk":"35"}}' \
  -w '\nHTTP_STATUS:%{http_code}\n'
```

- 返回 `HTTP_STATUS:204` 即触发成功。
- 查状态：`GET .../actions/runs?per_page=3`
- 查产物：`GET .../actions/runs/<run_id>/artifacts`
- 构建默认参数：`android-strict` **固定 true**（写死在 workflow `env`，非 workflow_dispatch 输入）、`platform-sdk=35`；产物是 KSU/Magisk 模块 zip。
  - 严禁改回 `false`：会导致 `com.tencent.tmgp.dfm` 启动 2–4 秒 SIGSEGV（pc=0，`GetPhysicalDeviceSurfaceFormatsKHR+3500`）。
  - 校验点在 `meson configure` 的选项值与 `build.ninja` 的 `-DANDROID_STRICT`；**不要查 `config.h`**（这两个宏来自 `pre_args`，不进 config.h）。
- 构建成功后 workflow 会自动创建 **pre-release**：tag `v<MESA_VER>-rc`，标题 `Turnip Enhanced <MESA_VER> RC`，资产 `turnip-enhanced.zip`。

### 四、发布与版本语义

- 当前每次成功构建都自动发 **pre-release（RC）**，模块版本号 `$(cat VERSION)-enhanced-rc`。
- 正式版应走独立 tag / release，版本号不带 `-rc`，需人工确认后发布。
- 项目文档约定：README.md 维护扩展清单、设备兼容性声明、安装前置要求。

