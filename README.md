# CxKitty_for_windows

在 Windows 上快捷地使用 CxKitty，原项目 <https://github.com/SocialSisterYi/CxKitty>

Python 运行时不再随仓库分发，改为由安装脚本按需下载：脚本会去 python.org 探测
3.13 系列中**最新的、且提供 Windows 嵌入式发行版的补丁版本**，下载后自动装好 pip 和全部依赖。
这样解释器和依赖都能保持在最新的安全补丁版本，不必等仓库更新。

## Windows

### 方法一：下载 zip

1. 点击右上角的 Code → Download ZIP
2. 解压后打开文件夹
3. 双击 `启动.bat`

首次运行会自动下载 Python 运行时并安装依赖（需要联网，视网速约几分钟），之后再运行就直接启动了。

### 方法二：使用 git

```bash
git clone https://github.com/renxinyileng/CxKitty_for_windows.git
cd CxKitty_for_windows
# 双击 启动.bat
```

### 单独准备环境

不想直接启动、只想先把环境装好，可以双击 `scripts\setup-windows.bat`，或在 PowerShell 里：

```powershell
.\scripts\setup-windows.ps1                              # 默认: 最新的 3.13.x + 清华源
.\scripts\setup-windows.ps1 -IndexUrl https://pypi.org/simple   # 换官方源
.\scripts\setup-windows.ps1 -PythonSeries 3.12           # 换 Python 系列
.\scripts\setup-windows.ps1 -Force                       # 重新下载并覆盖安装
```

装好的运行时在 `runtime\`，可以随时删掉重装。

## Linux / macOS

python.org 只为 Windows 提供嵌入式发行版，所以这两个平台改为使用系统上的 Python
建立 `.venv`（优先挑 3.13，找不到合适版本且装了 [uv](https://github.com/astral-sh/uv)
时会用 uv 自动下载一份）。

```bash
./scripts/setup-linux.sh     # Linux
./scripts/setup-macos.sh     # macOS

# 可选参数与 Windows 版一致
./scripts/setup-linux.sh --index-url https://pypi.org/simple
./scripts/setup-linux.sh --force
```

运行：

```bash
cd app && ../.venv/bin/python main.py
```

也可以直接用 Docker，见 [`app/README.md`](app/README.md) 的 Build 一节。

## 需要修改的配置

配置文件是 `app/config.yml`，题库搜索器等设置都在里面，具体说明见
[`app/README.md`](app/README.md)。

## 目录结构

```
├── 启动.bat            Windows 一键启动 (缺运行时会自动安装)
├── scripts/            各系统的环境准备脚本
│   ├── setup-windows.ps1 / .bat
│   ├── setup-linux.sh
│   └── setup-macos.sh
├── app/                CxKitty 程序本体 (main.py / config.yml / cxapi / resolver ...)
├── runtime/            Windows 嵌入式 Python, 由脚本生成, 不入库
└── .venv/              Linux/macOS 虚拟环境, 由脚本生成, 不入库
```

## 支持的 Python 版本

`>= 3.11, < 3.14`。3.10 已于 2026 年 10 月结束支持，故不再作为目标版本。
