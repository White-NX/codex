#!/usr/bin/env bash
#
# sync-custom.sh — 把「去指数退避」定制版跟随到官方新版本，并用 GitHub Actions 云端编译出新的 codex.exe。
#
# 用法:
#   bash sync-custom.sh                 跟随官方最新 stable release（默认，推荐）
#   bash sync-custom.sh --main          跟随官方 main 分支（最新开发版）
#   bash sync-custom.sh rust-v0.145.0   跟随指定 tag / commit
#   bash sync-custom.sh --no-wait       只推送触发 CI，不等待编译/下载
#
# 前置（本仓库已配好；换机器或重新 clone 后需重建）:
#   - git remote: origin = 你的 fork, upstream = openai/codex
#   - gh CLI 已登录，token 具备 repo + workflow 权限
#   - 分支 custom-no-backoff 上是自定义 commit（patch + workflow + 本脚本 + CLAUDE.md）
#
set -euo pipefail

# ---- 配置（换 fork 时改这里）----
BRANCH="custom-no-backoff"
FORK_REPO="White-NX/codex"
UPSTREAM_REPO="openai/codex"
WORKFLOW="build-custom.yml"
ARTIFACT="codex-windows-x64"
OUT_DIR="/d/projects/codex-bin"
EXPECTED_MARKERS=4          # CUSTOM PATCH 标记数：util.rs 1 + retry.rs 1 + model-provider-info 2

# ---- 参数 ----
WAIT=1
TARGET=""
case "${1:-}" in
  --no-wait) WAIT=0 ;;
  --main)    TARGET="upstream/main" ;;
  "")        TARGET="" ;;   # 稍后取官方最新 release tag
  *)         TARGET="$1" ;;
esac

cd "$(dirname "$0")"

echo "▶ 1/6 前置检查"
if [ -n "$(git status --porcelain)" ]; then
  echo "  ✗ 工作区有未提交改动，请先提交或 stash 再同步。" >&2
  git status --short >&2
  exit 1
fi
gh auth status >/dev/null 2>&1 || { echo "  ✗ gh 未登录，请先 gh auth login。" >&2; exit 1; }
echo "  ✓ 工作区干净，gh 已登录"

echo "▶ 2/6 拉取官方最新代码与 tag"
git fetch upstream --tags --prune

if [ -z "$TARGET" ]; then
  TARGET="$(gh release view --repo "$UPSTREAM_REPO" --json tagName -q .tagName)"
fi
echo "  → 目标版本: $TARGET"

echo "▶ 3/6 将定制 patch rebase 到 $TARGET"
git switch "$BRANCH"
if ! git rebase "$TARGET"; then
  {
    echo ""
    echo "  ✗ rebase 出现冲突，请手动处理："
    echo "     1) 定位你的改动（都带标记 CUSTOM PATCH）: grep -rn 'CUSTOM PATCH' codex-rs"
    echo "     2) 保留固定退避逻辑、合并官方其余改动后: git add <文件> && git rebase --continue"
    echo "     3) 处理完成后重新运行本脚本"
    echo "     若要放弃本次 rebase: git rebase --abort"
  } >&2
  exit 1
fi

echo "▶ 4/6 校验 patch 完整性"
markers=$(grep -rho "CUSTOM PATCH" \
  codex-rs/core/src/util.rs codex-rs/codex-client/src/retry.rs \
  codex-rs/model-provider-info/src/lib.rs | wc -l | tr -d ' ')
if [ "$markers" != "$EXPECTED_MARKERS" ]; then
  echo "  ✗ 期望 $EXPECTED_MARKERS 处 CUSTOM PATCH 标记，实际 $markers 处 —— patch 可能在 rebase 中丢失/损坏！" >&2
  echo "    请检查 util.rs、retry.rs 与 model-provider-info/src/lib.rs 后再推送。" >&2
  exit 1
fi
echo "  ✓ patch 完整（$markers 处标记）"

echo "▶ 5/6 推送到 fork（触发 CI 编译）"
old_run=$(gh run list --repo "$FORK_REPO" --workflow "$WORKFLOW" --branch "$BRANCH" \
  --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || true)
git push --force-with-lease origin "$BRANCH"

if [ "$WAIT" = "0" ]; then
  echo "▶ 完成（--no-wait）：CI 已触发，去 Actions 页面查看并下载 artifact："
  echo "   https://github.com/$FORK_REPO/actions"
  exit 0
fi

echo "▶ 6/6 等待 CI 编译并下载新二进制"
echo "  · 等待新 run 出现..."
run_id=""
for _ in $(seq 1 24); do
  run_id=$(gh run list --repo "$FORK_REPO" --workflow "$WORKFLOW" --branch "$BRANCH" \
    --limit 1 --json databaseId -q '.[0].databaseId' 2>/dev/null || true)
  [ -n "$run_id" ] && [ "$run_id" != "$old_run" ] && break
  sleep 5
done
if [ -z "$run_id" ] || [ "$run_id" = "$old_run" ]; then
  echo "  ✗ 未能确认新 run，请去 Actions 页面手动查看。" >&2
  exit 1
fi
echo "  · 监控 run $run_id（有 rust-cache，通常 10–30 分钟）..."
echo "    https://github.com/$FORK_REPO/actions/runs/$run_id"
if ! gh run watch "$run_id" --repo "$FORK_REPO" --exit-status --interval 60; then
  echo "  ✗ CI 编译失败。查看失败日志: gh run view $run_id --repo $FORK_REPO --log-failed" >&2
  exit 1
fi

echo "  · 下载 $ARTIFACT ..."
mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR/codex.exe"
gh run download "$run_id" --repo "$FORK_REPO" --name "$ARTIFACT" --dir "$OUT_DIR"
echo ""
echo "✅ 完成！新二进制："
ls -lh "$OUT_DIR/codex.exe"
"$OUT_DIR/codex.exe" --version 2>&1 | head -1 || true
