#!/usr/bin/env bash
#
# rime-wubipinyin 卸载 / 还原脚本
#
#   ./uninstall.sh              还原到 install.sh 建立的最近一次备份
#   ./uninstall.sh --list       列出所有可用备份
#   ./uninstall.sh --dir <path> 指定 Rime 用户目录
#
# 说明：本脚本只还原被本配置覆盖过的同名文件，不会删除你的用户词典、
#       userdb 或其它方案，也不会动 opencc/emoji.txt。
#
set -euo pipefail

RIME_DIR=""
LIST_ONLY=0

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --list) LIST_ONLY=1; shift ;;
    --dir)  RIME_DIR="${2:-}"; [ -n "$RIME_DIR" ] || die "--dir 需要一个路径"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "未知参数：$1" ;;
  esac
done

if [ -z "$RIME_DIR" ]; then
  case "$(uname -s)" in
    Darwin) RIME_DIR="$HOME/Library/Rime" ;;
    Linux)
      if [ -d "$HOME/.local/share/fcitx5/rime" ]; then RIME_DIR="$HOME/.local/share/fcitx5/rime"
      else RIME_DIR="$HOME/.config/ibus/rime"; fi ;;
    MINGW*|MSYS*|CYGWIN*) RIME_DIR="${APPDATA:-$HOME/AppData/Roaming}/Rime" ;;
    *) die "无法识别平台，请用 --dir 指定" ;;
  esac
fi

[ -d "$RIME_DIR" ] || die "Rime 目录不存在：$RIME_DIR"

# 备份目录名是 _backup_YYYYmmdd_HHMMSS，glob 展开即按时间升序，
# 循环到最后一个就是最新的。刻意不用 mapfile —— 那是 bash 4+ 才有的内建，
# 而 macOS 自带的仍是 bash 3.2。
LATEST=""
if [ "$LIST_ONLY" = 1 ]; then
  say "可用备份："
fi
for b in "$RIME_DIR"/_backup_*; do
  [ -d "$b" ] || continue
  LATEST="$b"
  [ "$LIST_ONLY" = 1 ] && \
    printf '    %s  (%s 个文件)\n' "$(basename "$b")" "$(ls -1 "$b" | wc -l | tr -d ' ')"
done

[ -n "$LATEST" ] || die "没有找到任何 _backup_* 备份目录"
[ "$LIST_ONLY" = 1 ] && exit 0
say "从备份还原：$(basename "$LATEST")"

count=0
for f in "$LATEST"/*; do
  [ -f "$f" ] || continue
  cp "$f" "$RIME_DIR/$(basename "$f")"
  count=$((count + 1))
done
say "已还原 $count 个文件"

case "$(uname -s)" in
  Darwin)
    SQ="/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel"
    [ -x "$SQ" ] && { say "重新部署"; "$SQ" --reload || warn "自动部署失败，请手动部署"; } ;;
  *) warn "请手动重新部署" ;;
esac

say "完成。备份目录仍保留在 $LATEST，确认无误后可自行删除。"
