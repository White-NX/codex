# CLAUDE.md — 定制 fork 维护指南

> 本文件供**任何经手本仓库的 AI agent**（Claude Code / codex / 其它）与人类维护者阅读。
> 官方的 agent 说明在同目录 `AGENTS.md` —— **请勿修改 `AGENTS.md`**，以免与上游 rebase 冲突。

## 这个 fork 是什么

本仓库是 **openai/codex 的个人定制 fork**，唯一目的：**去除模型 API 请求与 SSE 流的指数退避（exponential backoff）**，让失败重试以固定延迟进行。除此之外与官方完全一致，并持续跟随官方更新。

## 唯一的代码改动（共 3 行，务必保持最小）

所有自定义源码改动都带注释标记 `CUSTOM PATCH`。定位命令：
```bash
grep -rn "CUSTOM PATCH" codex-rs
```

| 文件 | 改动 | 层级 |
|---|---|---|
| `codex-rs/core/src/util.rs` | `backoff()` 指数因子改为固定（`powi(0)`） | SSE 流级重试 |
| `codex-rs/codex-client/src/retry.rs` | `backoff()` 指数项改为 `1u64` | HTTP 请求级重试 |

**刻意保留、未改动**：重试次数上限（`request_max_retries` / `stream_max_retries`）、服务端 `Retry-After` 尊重逻辑（`core/src/responses_retry.rs`）、随机抖动 jitter。

**⚠️ 铁律**：不要扩大改动范围。本 fork 的全部价值在于 diff 极小、易于永久跟随官方。任何新需求，先判断能否用配置（`~/.codex/config.toml`）而非改源码实现。

## 仓库约定

- **分支** `custom-no-backoff`：承载全部自定义 commit（patch + CI workflow + 本文件 + 同步脚本），始终 rebase 叠在官方发布 tag 之上。
- **remote**：`origin` = fork（`White-NX/codex`），`upstream` = `openai/codex`。
- **CI**：`.github/workflows/build-custom.yml`，用 GitHub 托管 `windows-latest` 编译，产出 artifact `codex-windows-x64`（内含 `codex.exe`）。

## 常见任务

### ① 跟随官方新版本（最常见）
**直接跑同步脚本**（它封装了全流程）：
```bash
bash sync-custom.sh            # 跟随官方最新 stable release（推荐）
bash sync-custom.sh --main     # 跟随最新开发版
```
脚本会：fetch upstream → rebase 到目标版本 → **校验 patch 完整性** → force-push → 等 CI 编译 → 下载新 `codex.exe` 到 `D:\projects\codex-bin\`。

### ② 编译
**绝不要在本地全量编译。** codex 是大型 Rust workspace，本地首编约 **1.5 小时**且占约 **8GB** 磁盘（曾撑爆磁盘）。**一律走 CI**：push 到 `custom-no-backoff` 会自动触发，或手动 `gh workflow run build-custom.yml --repo White-NX/codex --ref custom-no-backoff`。产物从 Actions run 的 Artifacts 下载。首次无缓存慢，之后有 `rust-cache`，增量编译约 10–30 分钟。

### ③ rebase 冲突处理
概率极低（只动 2 个稳定函数 + 独立新文件）。若发生：
1. `grep -rn "CUSTOM PATCH" codex-rs` 定位你的改动；
2. 保留固定退避逻辑，合并官方其余改动；
3. `git add <文件> && git rebase --continue`；
4. 完成后**务必**确认 `grep -rho "CUSTOM PATCH" codex-rs/core/src/util.rs codex-rs/codex-client/src/retry.rs | wc -l` 仍为 **2**。

### ④ 使用二进制
把 `D:\projects\codex-bin\codex.exe` 放进 PATH 或替换现有 codex。验证去退避生效：断流重连时日志 `Reconnecting… x/y` 的间隔应恒定（约 200ms）而非逐次翻倍。

## 关键坐标

| 项 | 值 |
|---|---|
| fork | `White-NX/codex` |
| 自定义分支 | `custom-no-backoff` |
| CI workflow | `build-custom`（`.github/workflows/build-custom.yml`） |
| artifact 名 | `codex-windows-x64` |
| 二进制输出目录 | `D:\projects\codex-bin\` |
| patch 标记 | `CUSTOM PATCH`（应恰好 2 处） |
