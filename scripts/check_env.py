#!/usr/bin/env python3
"""检查运行环境是否完整, 供启动脚本在开跑前判断"要不要先装环境"。

退出码 0 表示环境可用, 1 表示缺依赖 (并把缺的包名打到 stdout)。

只用标准库, 并且用 importlib.util.find_spec 而不是真的 import ——
find_spec 不执行模块代码, 既快 (onnxruntime / opencv 真 import 要一两秒),
也不会因为某个包运行时报错就误判成"没装"。

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


def main() -> int:
    quiet = "--quiet" in sys.argv[1:]
    missing = missing_packages()
    if missing:
        if not quiet:
            print(f"缺少依赖: {', '.join(missing)}")
        return 1
    if not quiet:
        print(f"环境可用 (python {sys.version.split()[0]})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
