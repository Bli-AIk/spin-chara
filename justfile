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
# 其他参数仍会透传给 LÖVE，例如 `just run -- --fused`。
run *args:
    @command -v {{love_bin}} >/dev/null 2>&1 || { echo "找不到 {{love_bin}}：请先安装 AUR 包 love-git，或设 LOVE_BIN=love" >&2; exit 127; }
    @set -- {{args}}; language=""; previous=""; for argument in "$@"; do if [ "$previous" = "language" ]; then language="$argument"; previous=""; elif [ "$argument" = "-l" ] || [ "$argument" = "--language" ]; then previous="language"; fi; done; [ "$previous" != "language" ] || { echo "-l/--language 缺少语言代码" >&2; exit 2; }; [ -z "$language" ] || [ -f "{{justfile_directory()}}/Localization/$language.json" ] || { echo "不支持的语言：$language" >&2; exit 2; }; cd "{{justfile_directory()}}" && SPIN_CHARA_LANGUAGE="$language" {{love_bin}} . "$@"

# 默认严格度 3（love.js）；`just check --all` 三种严格度一次对比。
# 只读，不改代码
check *args:
    @cd "{{justfile_directory()}}" && python3 Packager/check_compat.py {{args}}

# 运行模板集成测试（开发版 + 发布版）。Linux 下使用 Xvfb 提供无头显示。
test:
    @cd "{{justfile_directory()}}" && xvfb-run -a env ALSOFT_DRIVERS=null {{love_bin}} tests/template-update
    @cd "{{justfile_directory()}}" && xvfb-run -a env ALSOFT_DRIVERS=null SPIN_TEST_RELEASE=1 {{love_bin}} tests/template-update

# 打包工具（tkinter GUI）
pack:
    @cd "{{justfile_directory()}}" && python3 Packager/build_tool.py
