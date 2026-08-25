#!/usr/bin/env bash
#
# 为 CxKitty 准备 macOS 运行环境。
#
# python.org 只为 Windows 提供"嵌入式发行版", macOS 侧只有需要 sudo 的 .pkg 安装器,
# 因此这里的做法是: 找一个可用的 Python (优先 3.13), 建立 .venv 并装好依赖。
# 若系统里一个合适的解释器都没有, 而机器上装了 uv, 就用 uv 下载一份独立构建的
# 最新 3.13 —— 这是免 sudo 情况下最接近"自动下载指定版本"的方案。
#
# Intel 与 Apple Silicon 均可, 全部依赖都提供对应的 cp313 wheel。
#
# 用法:
#   ./scripts/setup-macos.sh
#   ./scripts/setup-macos.sh --index-url https://pypi.org/simple
#   ./scripts/setup-macos.sh --force
#
set -euo pipefail

PYTHON_SERIES="3.13"
# 与 app/pyproject.toml 的 requires-python 保持一致
MIN_MINOR=11
MAX_MINOR=13
INDEX_URL=""
FORCE=0

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname -- "$SCRIPT_DIR")"
VENV_DIR="$REPO_ROOT/.venv"
REQUIREMENTS="$REPO_ROOT/app/requirements.txt"

step() { printf '\033[36m==> %s\033[0m\n' "$*"; }
note() { printf '\033[90m    %s\033[0m\n' "$*"; }
ok()   { printf '\033[32m==> %s\033[0m\n' "$*"; }
die()  { printf '\033[31m错误: %s\033[0m\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --index-url) INDEX_URL="${2:-}"; shift 2 ;;
        --index-url=*) INDEX_URL="${1#*=}"; shift ;;
        --python-series) PYTHON_SERIES="${2:-}"; shift 2 ;;
        --python-series=*) PYTHON_SERIES="${1#*=}"; shift ;;
        --force) FORCE=1; shift ;;
        -h|--help) sed -n '2,22p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) die "未知参数: $1" ;;
    esac
done

# 判断某个解释器版本是否落在 [3.$MIN_MINOR, 3.$MAX_MINOR] 区间内
version_supported() {
    "$1" - <<EOF >/dev/null 2>&1
import sys
raise SystemExit(0 if sys.version_info[0] == 3 and $MIN_MINOR <= sys.version_info[1] <= $MAX_MINOR else 1)
EOF
}

find_python() {
    # 优先目标系列, 然后从新到旧回退; Homebrew 的 keg-only 路径也一并找一下
    local candidates=("python${PYTHON_SERIES}")
    local minor
    for (( minor=MAX_MINOR; minor>=MIN_MINOR; minor-- )); do
        candidates+=("python3.${minor}")
    done
    candidates+=("python3")

    local candidate path
    for candidate in "${candidates[@]}"; do
        path="$(command -v "$candidate" 2>/dev/null || true)"
        [ -n "$path" ] || continue
        if version_supported "$path"; then
            printf '%s' "$path"
            return 0
        fi
    done

    # Homebrew 装的 python@3.x 不一定在 PATH 上
    local brew_prefix
    brew_prefix="$(brew --prefix 2>/dev/null || true)"
    if [ -n "$brew_prefix" ]; then
        for (( minor=MAX_MINOR; minor>=MIN_MINOR; minor-- )); do
            path="$brew_prefix/opt/python@3.${minor}/bin/python3.${minor}"
            if [ -x "$path" ] && version_supported "$path"; then
                printf '%s' "$path"
                return 0
            fi
        done
    fi
    return 1
}

install_python_with_uv() {
    command -v uv >/dev/null 2>&1 || return 1
    step "系统里没有合适的 Python, 改用 uv 下载 ${PYTHON_SERIES} 独立构建..."
    uv python install "$PYTHON_SERIES" >&2 || return 1
    uv python find "$PYTHON_SERIES" 2>/dev/null
}

step "查找可用的 Python (需要 3.${MIN_MINOR} ~ 3.${MAX_MINOR}, 首选 ${PYTHON_SERIES})..."
PYTHON="$(find_python || true)"
if [ -z "$PYTHON" ]; then
    PYTHON="$(install_python_with_uv || true)"
fi
if [ -z "$PYTHON" ]; then
    cat >&2 <<EOF

没有找到 3.${MIN_MINOR} ~ 3.${MAX_MINOR} 范围内的 Python。任选一种方式装好后重新运行本脚本:

  # Homebrew (推荐)
  brew install python@${PYTHON_SERIES}

  # 不想动系统环境 (免 sudo, 自动下载对应版本)
  curl -LsSf https://astral.sh/uv/install.sh | sh
  uv python install ${PYTHON_SERIES}

  # 或从 https://www.python.org/downloads/macos/ 下载官方安装包

EOF
    die "缺少可用的 Python 解释器"
fi
note "使用 $PYTHON ($("$PYTHON" -V 2>&1)) / $(uname -m)"

[ -f "$REQUIREMENTS" ] || die "找不到 $REQUIREMENTS"

if [ -d "$VENV_DIR" ] && [ "$FORCE" -eq 1 ]; then
    step "删除已有的 .venv (--force)..."
    rm -rf -- "$VENV_DIR"
fi

if [ ! -x "$VENV_DIR/bin/python" ]; then
    step "创建虚拟环境 $VENV_DIR ..."
    "$PYTHON" -m venv "$VENV_DIR" || die "创建 venv 失败"
else
    note ".venv 已存在, 直接复用 (需要重建请加 --force)"
fi

PIP_ARGS=()
REQ_FILE="$REQUIREMENTS"
TMP_REQ=""
cleanup() { [ -n "$TMP_REQ" ] && rm -f -- "$TMP_REQ" || true; }
trap cleanup EXIT

if [ -n "$INDEX_URL" ]; then
    PIP_ARGS+=(--index-url "$INDEX_URL")
    # requirements.txt 里自带的 --index-url 优先级高于命令行, 想覆盖就得先把那行去掉
    TMP_REQ="$(mktemp)"
    grep -v '^[[:space:]]*--index-url' "$REQUIREMENTS" > "$TMP_REQ"
    REQ_FILE="$TMP_REQ"
    note "使用镜像源 $INDEX_URL"
fi

step "升级 pip ..."
"$VENV_DIR/bin/python" -m pip install --quiet --upgrade pip "${PIP_ARGS[@]+"${PIP_ARGS[@]}"}"

# 不指定 --index-url 时, pip 会沿用 requirements.txt 里自带的镜像源 (清华源)
step "安装项目依赖 ..."
"$VENV_DIR/bin/python" -m pip install -r "$REQ_FILE" "${PIP_ARGS[@]+"${PIP_ARGS[@]}"}"

step "环境自检 ..."
# 与启动器共用 scripts/check_env.py, 免得两边对"环境完整"的定义走偏
# pip 只看 dist-info 元数据, 包目录被手工删掉时它会认为"已安装"而不补装, 故这里兜一层
"$VENV_DIR/bin/python" "$SCRIPT_DIR/check_env.py" ||
    die "依赖安装完成但环境自检未通过, 请检查上面的 pip 输出, 或加 --force 重建 .venv"

ok "环境准备完成"
echo
echo "运行方式:  ./启动.sh   (菜单; 也可以 cd app && ../.venv/bin/python main.py)"
echo "改配置:    ./启动.sh 选 [2], 或 cd app && ../.venv/bin/python main.py --config"
echo "配置文件:  app/config.yml"
