#!/usr/bin/env bash
#
# Linux / macOS 启动器 (对应 windows 的 启动.bat)。
#
# 与 windows 的区别: 这里**不会**自动装 Python。
# python.org 只为 windows 提供免安装的嵌入式发行版, 所以 windows 上启动器可以
# 悄悄下载一份便携解释器塞进 runtime\ 了事; Linux/macOS 上装解释器要动系统
# (包管理器 / pyenv / uv), 装什么、装到哪应该由你决定, 故这里只检测并提示,
# 真正的安装交给 scripts/setup-linux.sh 或 scripts/setup-macos.sh。
#
set -uo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

VENV_PY=".venv/bin/python"
case "$(uname -s)" in
    Darwin) SETUP_SCRIPT="./scripts/setup-macos.sh" ;;
    *)      SETUP_SCRIPT="./scripts/setup-linux.sh" ;;
esac

red()    { printf '\033[31m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }

# ---- 环境检测 (只提示, 不自动安装) ----

if [ ! -x "$VENV_PY" ]; then
    red "未检测到 Python 环境: 缺少 $VENV_PY"
    yellow "本平台不会自动安装解释器, 请先执行:"
    echo "    $SETUP_SCRIPT"
    yellow "装好后再运行本脚本。(换镜像源: $SETUP_SCRIPT --index-url https://pypi.org/simple)"
    exit 1
fi

if ! "$VENV_PY" scripts/check_env.py; then
    red "Python 环境不完整 (依赖缺失或装到一半)"
    yellow "本平台不会自动补装, 请执行:"
    echo "    $SETUP_SCRIPT          # 补装缺失的依赖"
    echo "    $SETUP_SCRIPT --force  # 依然不行就重建 .venv"
    exit 1
fi

# ---- 菜单 ----

run_app()    { (cd app && "../$VENV_PY" main.py); }        # 必须以 app/ 为工作目录
run_config() { (cd app && "../$VENV_PY" main.py --config); }
run_check()  { "$VENV_PY" scripts/smoke_test.py; }

while true; do
    echo "============================================"
    echo " CxKitty  超星学习通答题姬"
    echo "============================================"
    echo " [1] 启动程序"
    echo " [2] 配置编辑器 (改 app/config.yml: 题库、大模型答题等)"
    echo " [3] 环境自检 (离线冒烟测试, 不访问超星接口)"
    echo " [0] 退出"
    echo
    # 标准输入结束 (以管道方式运行) 时直接退出, 不空转
    if ! read -r -p "请输入序号后回车 (直接回车即启动程序): " sel; then
        echo
        exit 0
    fi
    echo
    case "${sel:-1}" in
        1) run_app; code=$?; echo; echo "程序已退出 (返回码 $code)" ;;
        2) run_config ;;
        3) run_check ;;
        0) exit 0 ;;
        *) echo "无效的选项: $sel"; echo; continue ;;
    esac
    echo
    read -r -p "按回车返回菜单 (直接 Ctrl+C 退出)... " _ || exit 0
    echo
done
