# spin-chara / Nexus02 —— 开发任务入口
#
# 为什么是 love-git 而不是 love：
#   conf.lua 里 t.version = "12.0"，本工程面向 LÖVE 12。
#   发行版官方包 love 装出来是 /usr/bin/love（11.5），
#   AUR 的 love-git 装出来是 /usr/bin/love-git（12.0 "Bestest Friend"）。
#   两者在系统里可以共存，但跑本工程必须用后者。
#   想换回官方包时：LOVE_BIN=love just run

love_bin := env("LOVE_BIN", "love-git")

# 不带参数运行 `just` 时默认启动游戏
default: run

# LÖVE 以 cwd 作为源目录，游戏里的 io.open(".reload_trigger") 和 Resources/
# 相对路径都依赖这一点，所以先 cd 到 justfile 所在目录再启动。
# `-l/--language` 可覆盖本次启动语言，例如 `just run -l en`。
# `-w/--wave` 直接进入指定回合，例如 `just run -w 3`。
# `--workspace` 指定窗口开在哪个工作区：数字 = 对应工作区（默认 9），
# auto = 当前工作区。做法是给本次启动一个专属窗口类（SDL_APP_ID），再向
# Hyprland 注册一条"该类 -> 目标工作区"的运行时规则（no_initial_focus，
# 不抢焦点）；规则不写进 hyprland 配置，reload 即消失；没有 hyprctl 或不
# 在 Hyprland 下会退化成普通启动，不影响游戏本身。
# 其他参数仍会透传给 LÖVE，例如 `just run -- --fused`。
run *args:
    #!/bin/sh
    set -eu
    # shebang recipe 拿不到 just 的参数，跟原来的写法一样用 {{args}} 自己装回来
    set -- {{args}}
    command -v {{love_bin}} >/dev/null 2>&1 || { echo "找不到 {{love_bin}}：请先安装 AUR 包 love-git，或设 LOVE_BIN=love" >&2; exit 127; }
    language=""; workspace="9"; wave=""; previous=""
    for argument in "$@"; do
      if [ "$previous" = "language" ]; then language="$argument"; previous=""
      elif [ "$previous" = "workspace" ]; then workspace="$argument"; previous=""
      elif [ "$previous" = "wave" ]; then wave="$argument"; previous=""
      elif [ "$argument" = "-l" ] || [ "$argument" = "--language" ]; then previous="language"
      elif [ "$argument" = "-w" ] || [ "$argument" = "--wave" ]; then previous="wave"
      elif [ "$argument" = "--workspace" ]; then previous="workspace"
      fi
    done
    [ "$previous" != "language" ] || { echo "-l/--language 缺少语言代码" >&2; exit 2; }
    [ "$previous" != "wave" ] || { echo "-w/--wave 缺少回合编号" >&2; exit 2; }
    case "$wave" in
      ""|1|2|3|4|5|6|7|8|9|10) ;;
      *) echo "-w/--wave 只接受 1–10：$wave" >&2; exit 2 ;;
    esac
    [ "$previous" != "workspace" ] || { echo "-w/--workspace 缺少参数（数字或 auto）" >&2; exit 2; }
    [ -z "$language" ] || [ -f "{{justfile_directory()}}/Localization/$language.json" ] || { echo "不支持的语言：$language" >&2; exit 2; }
    [ -n "$workspace" ] || workspace="9"
    case "$workspace" in
      auto) app_id="spin-chara-auto" ;;
      *[!0-9]*) echo "-w/--workspace 只接受数字或 auto：$workspace" >&2; exit 2 ;;
      *)
        app_id="spin-chara-ws$workspace"
        if command -v hyprctl >/dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
          hyprctl eval "hl.window_rule({ name = \"spin-chara-run-ws$workspace\", match = { class = \"^$app_id\$\" }, workspace = $workspace, no_initial_focus = true })" >/dev/null 2>&1 \
            || echo "提示：注册工作区规则失败，窗口会开在当前工作区" >&2
        fi
        ;;
    esac
    cd "{{justfile_directory()}}" && SDL_APP_ID="$app_id" SPIN_CHARA_LANGUAGE="$language" SPIN_CHARA_WAVE="$wave" {{love_bin}} . "$@"

# 默认严格度 3（love.js）；`just check --all` 三种严格度一次对比。
# 只读，不改代码
check *args:
    @cd "{{justfile_directory()}}" && python3 Packager/check_compat.py {{args}}

# 运行模板集成测试（开发版 + 发布版）。Linux 下使用 Xvfb 提供无头显示。
test:
    @cd "{{justfile_directory()}}" && xvfb-run -a env ALSOFT_DRIVERS=null {{love_bin}} tests/template-update
    @cd "{{justfile_directory()}}" && xvfb-run -a env ALSOFT_DRIVERS=null SPIN_TEST_RELEASE=1 {{love_bin}} tests/template-update

# 录制第三回合完整弹幕（玩家无敌 + 逐帧 1:1 抓取），再合成 mp4。
# 画面取自 640x480 的游戏主画布，用 ffmpeg 最近邻放大 scale 倍，因此不受窗口
# 尺寸、合成器、虚拟屏分辨率和光标影响，同一命令重跑逐帧一致。
# 用法：just record-wave3 [输出路径] [放大倍数]，例如 just record-wave3 out.mp4 1
record-wave3 out="recordings/wave03-barrage.mp4" scale="2":
    #!/bin/sh
    set -eu
    command -v {{love_bin}} >/dev/null 2>&1 || { echo "找不到 {{love_bin}}：请先安装 AUR 包 love-git，或设 LOVE_BIN=love" >&2; exit 127; }
    command -v ffmpeg >/dev/null 2>&1 || { echo "找不到 ffmpeg" >&2; exit 127; }
    # 帧目录交给 mktemp 管：上一轮残留的高编号帧会被 image2 解复用器一起编进去
    frames=$(mktemp -d)
    trap 'rm -rf "$frames"' EXIT INT TERM
    cd "{{justfile_directory()}}"
    xvfb-run -a env ALSOFT_DRIVERS=null \
        SPIN_CHARA_WAVE=3 SPIN_CHARA_INVINCIBLE=1 SPIN_RECORD_DIR="$frames" \
        {{love_bin}} tests/wave03-record
    count=$(ls -1 "$frames" | wc -l)
    [ "$count" -gt 1000 ] || { echo "帧数异常：$count" >&2; exit 1; }
    if [ "{{scale}}" = "1" ]; then
        vf="format=yuv420p"
    else
        vf="scale=iw*{{scale}}:ih*{{scale}}:flags=neighbor,format=yuv420p"
    fi
    mkdir -p "$(dirname '{{out}}')"
    ffmpeg -y -framerate 60 -i "$frames/%05d.png" -vf "$vf" \
        -c:v libx264 -preset slow -crf 12 -tune animation -movflags +faststart \
        -r 60 "{{out}}"
    ffprobe -v error -select_streams v:0 \
        -show_entries stream=nb_frames,width,height,r_frame_rate:format=duration \
        -of default=nw=1 "{{out}}"

# 打包工具（tkinter GUI）
pack:
    @cd "{{justfile_directory()}}" && python3 Packager/build_tool.py
