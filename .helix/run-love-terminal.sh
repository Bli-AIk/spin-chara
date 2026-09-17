#!/bin/sh
set -eu

hold=0
case "${1:-}" in
  --hold)
    hold=1
    ;;
  "")
    ;;
  *)
    echo "usage: $0 [--hold]" >&2
    exit 64
    ;;
esac

repo_root="$(git rev-parse --show-toplevel)"
title="SoulEngine-Fork"

# 启动命令统一交给项目根的 justfile（它固定用 love-git，即 LÖVE 12），
# 这样换引擎 / 加启动参数只需要改一个地方。
if [ "$hold" -eq 1 ]; then
  shell_cmd='cd "$1"; just run; exit_code=$?; echo; echo love exited with status $exit_code; exec zsh -l'
else
  shell_cmd='cd "$1"; exec just run'
fi

terminal=""
if [ -n "${KITTY_WINDOW_ID:-}" ] || [ "${TERM:-}" = "xterm-kitty" ]; then
  terminal="kitty"
elif [ -n "${XTERM_VERSION:-}" ]; then
  terminal="xterm"
else
  case "${TERM:-}" in
    xterm|xterm-*)
      terminal="xterm"
      ;;
  esac
fi

case "$terminal" in
  kitty)
    if [ "$hold" -eq 1 ]; then
      kitty --detach --hold --title "$title" --directory "$repo_root" zsh -lc "$shell_cmd" sh "$repo_root" >/dev/null 2>&1
      exit 0
    fi
    kitty --detach --title "$title" --directory "$repo_root" zsh -lc "$shell_cmd" sh "$repo_root" >/dev/null 2>&1
    exit 0
    ;;
  xterm)
    if [ "$hold" -eq 1 ]; then
      xterm -hold -T "$title" -e zsh -lc "$shell_cmd" sh "$repo_root" >/dev/null 2>&1 &
      exit 0
    fi
    xterm -T "$title" -e zsh -lc "$shell_cmd" sh "$repo_root" >/dev/null 2>&1 &
    exit 0
    ;;
  *)
    echo "unsupported terminal: TERM=${TERM:-}, KITTY_WINDOW_ID=${KITTY_WINDOW_ID:-}, XTERM_VERSION=${XTERM_VERSION:-}" >&2
    exit 1
    ;;
esac
