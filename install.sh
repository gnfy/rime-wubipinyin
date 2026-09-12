#!/usr/bin/env bash
#
# rime-wubipinyin 安装脚本
#
#   ./install.sh                 安装（自动识别平台，自动备份旧配置）
#   ./install.sh --no-emoji      跳过 emoji 词表下载
#   ./install.sh --dir <path>    指定 Rime 用户目录（自动识别失败时用）
#   ./install.sh --dry-run       只打印将要做什么，不动文件
#
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rime"

# emoji 词表来自 oh-my-rime（GPL-3.0），因许可证不兼容，本仓库不打包分发，
# 改为安装时由用户自行下载。固定 commit 保证可复现。
EMOJI_REPO_COMMIT="660471510ac3625734a8991947e2a800de68cbe0"
EMOJI_URL="https://raw.githubusercontent.com/Mintimate/oh-my-rime/${EMOJI_REPO_COMMIT}/opencc/emoji.txt"
EMOJI_SHA256="a807c3cd7e20d49b9642ef99a09aa5d2f2a5a3cc5dc7b5289206a1f1f61a2f98"

WITH_EMOJI=1
DRY_RUN=0
RIME_DIR=""

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
run()  { if [ "$DRY_RUN" = 1 ]; then printf '    would run: %s\n' "$*"; else "$@"; fi; }

while [ $# -gt 0 ]; do
  case "$1" in
    --no-emoji) WITH_EMOJI=0; shift ;;
    --dry-run)  DRY_RUN=1; shift ;;
    --dir)      RIME_DIR="${2:-}"; [ -n "$RIME_DIR" ] || die "--dir 需要一个路径"; shift 2 ;;
    -h|--help)  sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)          die "未知参数：$1（用 --help 看用法）" ;;
  esac
done

[ -d "$SRC_DIR" ] || die "找不到 rime/ 目录，请在仓库根目录运行本脚本"

# ---------------------------------------------------------------
# 1. 定位 Rime 用户目录
# ---------------------------------------------------------------
detect_rime_dir() {
  case "$(uname -s)" in
    Darwin)
      echo "$HOME/Library/Rime" ;;                      # 鼠鬚管 Squirrel
    Linux)
      if   [ -d "$HOME/.local/share/fcitx5/rime" ]; then echo "$HOME/.local/share/fcitx5/rime"
      elif [ -d "$HOME/.config/ibus/rime" ];        then echo "$HOME/.config/ibus/rime"
      elif command -v fcitx5 >/dev/null 2>&1;       then echo "$HOME/.local/share/fcitx5/rime"
      else echo "$HOME/.config/ibus/rime"; fi ;;
    MINGW*|MSYS*|CYGWIN*)
      echo "${APPDATA:-$HOME/AppData/Roaming}/Rime" ;;  # 小狼毫 Weasel
    *)
      echo "" ;;
  esac
}

[ -n "$RIME_DIR" ] || RIME_DIR="$(detect_rime_dir)"
[ -n "$RIME_DIR" ] || die "无法识别平台，请用 --dir 指定 Rime 用户目录"

say "平台：$(uname -s)"
say "Rime 用户目录：$RIME_DIR"
[ "$DRY_RUN" = 1 ] && warn "dry-run 模式，不会真正写入"

run mkdir -p "$RIME_DIR"

# ---------------------------------------------------------------
# 2. 备份现有配置
# ---------------------------------------------------------------
if [ -n "$(ls -A "$RIME_DIR" 2>/dev/null || true)" ]; then
  BACKUP="$RIME_DIR/_backup_$(date +%Y%m%d_%H%M%S)"
  say "备份现有配置到 $BACKUP"
  if [ "$DRY_RUN" = 0 ]; then
    mkdir -p "$BACKUP"
    # 只备份会被覆盖的同名文件，不动用户词典和 userdb
    for f in "$SRC_DIR"/*.yaml; do
      b="$(basename "$f")"
      [ -f "$RIME_DIR/$b" ] && cp "$RIME_DIR/$b" "$BACKUP/" || true
    done
    say "已备份 $(ls -1 "$BACKUP" 2>/dev/null | wc -l | tr -d ' ') 个文件"
  fi
fi

# ---------------------------------------------------------------
# 3. 复制配置
# ---------------------------------------------------------------
say "安装配置文件"
if [ "$DRY_RUN" = 0 ]; then
  # 用户词典若已存在就不覆盖，避免抹掉使用者自己造的词
  for f in "$SRC_DIR"/*; do
    b="$(basename "$f")"
    if [ -d "$f" ]; then
      mkdir -p "$RIME_DIR/$b" && cp -R "$f/." "$RIME_DIR/$b/"
    elif [ "$b" = "wubi86_jidian_user.dict.yaml" ] && [ -f "$RIME_DIR/$b" ]; then
      warn "保留你已有的 $b（未覆盖）"
    else
      cp "$f" "$RIME_DIR/$b"
    fi
  done
else
  printf '    would copy: %s/* -> %s/\n' "$SRC_DIR" "$RIME_DIR"
fi

# ---------------------------------------------------------------
# 4. emoji 词表（可选，GPL-3.0，不随本仓库分发）
# ---------------------------------------------------------------
if [ "$WITH_EMOJI" = 1 ]; then
  say "下载 emoji 词表（来自 oh-my-rime，GPL-3.0）"
  if [ "$DRY_RUN" = 0 ]; then
    TMP="$(mktemp)"
    if curl -fsSL -o "$TMP" "$EMOJI_URL"; then
      if command -v shasum >/dev/null 2>&1; then
        got="$(shasum -a 256 "$TMP" | awk '{print $1}')"
      else
        got="$(sha256sum "$TMP" | awk '{print $1}')"
      fi
      if [ "$got" = "$EMOJI_SHA256" ]; then
        mkdir -p "$RIME_DIR/opencc"
        mv "$TMP" "$RIME_DIR/opencc/emoji.txt"
        say "emoji 词表校验通过并安装"
      else
        rm -f "$TMP"
        warn "emoji 词表校验不匹配（上游可能已更新），跳过"
        warn "  期望 $EMOJI_SHA256"
        warn "  实际 $got"
      fi
    else
      rm -f "$TMP"
      warn "emoji 词表下载失败（可能需要代理），跳过"
    fi
    # 缺了 emoji.txt 也不影响输入法：Rime 的 simplifier 在 OpenCC 数据
    # 加载失败时会静默跳过（librime simplifier.cc: `if (!opencc_) return translation;`）
  fi
else
  say "按要求跳过 emoji 词表"
fi

# ---------------------------------------------------------------
# 5. 重新部署
# ---------------------------------------------------------------
if [ "$DRY_RUN" = 0 ]; then
  case "$(uname -s)" in
    Darwin)
      SQ="/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel"
      if [ -x "$SQ" ]; then
        say "触发鼠鬚管重新部署"
        "$SQ" --reload || warn "自动部署失败，请手动点菜单栏「重新部署」"
      else
        warn "未找到鼠鬚管，请先安装：brew install --cask squirrel"
      fi ;;
    *)
      warn "请手动重新部署：小狼毫右键菜单「重新部署」，或 Linux 下 ibus-daemon -drx / fcitx5 重启" ;;
  esac
fi

cat <<'EOF'

──────────────────────────────────────────────
安装完成。接下来：

  1. 在输入法菜单（macOS 默认 Ctrl+`）里选择方案
       极点五笔·拼音辅助   ← 推荐，五笔为主，z 引导拼音
       极点五笔            ← 纯五笔
  2. 打 g 看看候选后面有没有五笔编码提示
  3. 打 zzhongguo 试试拼音辅助 + 编码标注
  4. Ctrl+Shift+E 开关 emoji

完整说明见 README.md，设计取舍见 docs/design.md
──────────────────────────────────────────────
EOF
