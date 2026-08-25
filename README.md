# CxKitty_for_windows

在 Windows 上快捷地使用 CxKitty，原项目 <https://github.com/SocialSisterYi/CxKitty>

程序以命令行 / TUI 方式运行，不启动浏览器、不渲染网页，目的是减少不必要的性能开销。

Python 运行时不再随仓库分发，改为由安装脚本按需下载：脚本会去 python.org 探测
3.13 系列中**最新的、且提供 Windows 嵌入式发行版的补丁版本**，下载后自动装好 pip 和全部依赖。
这样解释器和依赖都能保持在最新的安全补丁版本，不必等仓库更新。

## Windows

### 方法一：下载 zip

1. 点击右上角的 Code → Download ZIP
2. 解压后打开文件夹
3. 双击 `启动.bat`

首次运行会自动下载 Python 运行时并安装依赖（需要联网，视网速约几分钟），之后再运行就直接启动了。

`启动.bat` 是个菜单，直接回车即为启动程序：

```
[1] 启动程序
[2] 配置编辑器 (改 app\config.yml: 题库、大模型答题等)
[3] 环境自检 (离线冒烟测试, 不访问超星接口)
[4] 重装运行时与依赖
[0] 退出
```

`[2]` 打开的是控制台里的可视化配置编辑器（也就是 `main.py --config`），可以逐项修改任务开关、
搜索器调度策略，以及增删题库 / 大模型答题器；保存时保留 `config.yml` 里的全部注释，
并自动备份为 `config.yml.bak`。程序退出后会回到该菜单，改完配置可以直接再启动。

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

也可以用 Docker（镜像基于 `python:3.13`，Linux 下装的是 headless 版 OpenCV，无需额外 GUI 系统库）：

```bash
docker build --tag cx-kitty app/
```

完整的容器运行参数（目录映射、日志大小限制等）见 [`app/README.md`](app/README.md) 的 Build 一节。

## 需要修改的配置

配置文件是 `app/config.yml`，题库搜索器、大模型答题器等设置都在里面，具体说明见
[`app/README.md`](app/README.md)。

不想手写 YAML 就用配置编辑器：`启动.bat` 选 `[2]`，或

```bash
cd app && ../.venv/bin/python main.py --config   # Linux/macOS
```

自动答题除了各类题库后端，现在也支持**大模型在线答题**（OpenAI 兼容接口，内置 DeepSeek、
Kimi、通义千问、智谱、硅基流动、Gemini、火山方舟、本地 Ollama 等预设）。默认策略是
**题库优先**：题库查得到就不请求 AI，查不到才交给 AI，多个 AI 的作答会交叉对比取共识。

## 目录结构

```
├── 启动.bat            Windows 一键启动菜单 (缺运行时会自动安装)
├── scripts/            各系统的环境准备脚本
│   ├── setup-windows.ps1 / .bat
│   ├── setup-linux.sh
│   └── setup-macos.sh
├── app/                CxKitty 程序本体 (main.py / config.yml / cxapi / resolver ...)
├── runtime/            Windows 嵌入式 Python, 由脚本生成, 不入库
└── .venv/              Linux/macOS 虚拟环境, 由脚本生成, 不入库
```

## 支持的 Python 版本

`>= 3.11, < 3.14`。3.10 将于 2026 年 10 月结束安全支持，且 3.10.11 已是该系列
最后一个提供 Windows 嵌入式发行版的版本（之后的补丁版只发布源码），故不再作为目标版本。
