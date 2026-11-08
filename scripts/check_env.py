#!/usr/bin/env python3
"""检查运行环境是否完整, 供启动脚本在开跑前判断"要不要先装环境"。

退出码 0 表示环境可用, 1 表示依赖缺失或版本不符合锁定要求。

用 importlib.util.find_spec 检查主要模块, 避免加载 onnxruntime / opencv。
再用 packaging 解析 requirements.txt, 按当前平台检查全部锁定依赖的元数据。
检查不需要联网; packaging 缺失时也返回 1, 交给安装脚本补装。

用法:
    <解释器> scripts/check_env.py          # 只看退出码
    <解释器> scripts/check_env.py --quiet   # 不打印任何内容
"""
import sys

# 打印中文前先兜底 UTF-8: windows 上 stdout 被重定向时会退回 locale 编码
for _stream in (sys.stdout, sys.stderr):
    if hasattr(_stream, "reconfigure"):
        _stream.reconfigure(encoding="utf-8", errors="replace")

import importlib.util  # noqa: E402  (放在编码兜底之后, 保证异常信息也能打出来)
from importlib import metadata  # noqa: E402
from pathlib import Path  # noqa: E402

REQUIREMENTS = Path(__file__).resolve().parent.parent / "app" / "requirements.txt"

# import 名 -> pip 包名。挑的是各条主要链路上的包, 缺一个都跑不起来:
# TUI、网络、解析、验证码识别 (opencv/numpy/onnxruntime/ddddocr)、
# 二维码登录、加密、题库/大模型答题、配置编辑器
REQUIRED = {
    "rich": "rich",
    "requests": "requests",
    "bs4": "beautifulsoup4",
    "lxml": "lxml",
    "yaml": "pyyaml",
    "jsonpath": "jsonpath-python",
    "dataclasses_json": "dataclasses-json",
    "yarl": "yarl",
    "Crypto": "pycryptodome",
    "numpy": "numpy",
    # linux (含 docker) 上装的是 headless 版, 两者提供同一个 cv2
    "cv2": "opencv-python[-headless]",
    "onnxruntime": "onnxruntime",
    "ddddocr": "ddddocr",
    "qrcode": "qrcode",
    "PIL": "pillow",
    "openai": "openai",
    "ruamel.yaml": "ruamel.yaml",
}


def missing_packages() -> list[str]:
    """返回缺失的 pip 包名列表"""
    missing = []
    for module, package in REQUIRED.items():
        try:
            found = importlib.util.find_spec(module) is not None
        except (ImportError, ValueError):
            # 父包都没装时 find_spec 会抛 ImportError
            found = False
        if not found:
            missing.append(package)
    return missing


def version_issues(requirements: Path = REQUIREMENTS) -> list[str]:
    """检查当前平台的全部锁定版本, 包括间接依赖。"""
    try:
        from packaging.requirements import InvalidRequirement, Requirement
        from packaging.version import InvalidVersion
    except ImportError:
        return ["缺少 packaging, 无法检查依赖版本"]

    try:
        lines = requirements.read_text(encoding="utf-8-sig").splitlines()
    except OSError as exc:
        return [f"无法读取依赖清单: {exc}"]

    issues = []
    for number, line in enumerate(lines, 1):
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("--index-url "):
            continue
        try:
            requirement = Requirement(line)
        except InvalidRequirement:
            issues.append(f"依赖清单第 {number} 行无效: {line}")
            continue
        if requirement.marker and not requirement.marker.evaluate():
            continue
        try:
            installed = metadata.version(requirement.name)
        except metadata.PackageNotFoundError:
            issues.append(f"缺少 {requirement.name}")
            continue
        try:
            matches = requirement.specifier.contains(installed, prereleases=True)
        except InvalidVersion:
            matches = False
        if not matches:
            issues.append(
                f"{requirement.name}: 已安装 {installed}, 需要 {requirement.specifier}"
            )
    return issues


def main() -> int:
    quiet = "--quiet" in sys.argv[1:]
    # 避免不受支持的 Python 跳过清单里所有 python_version 标记后误报通过。
    if not (3, 11) <= sys.version_info[:2] < (3, 14):
        if not quiet:
            print("Python 版本不受支持, 需要 >=3.11,<3.14, 请重新准备运行环境")
        return 1
    missing = missing_packages()
    issues = version_issues()
    if missing or issues:
        if not quiet:
            if missing:
                print(f"缺少依赖: {', '.join(missing)}")
            for issue in issues:
                print(f"依赖需要同步: {issue}")
        return 1
    if not quiet:
        print(f"环境可用 (python {sys.version.split()[0]})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
