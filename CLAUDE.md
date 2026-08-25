# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 这个仓库是什么

`SocialSisterYi/CxKitty`（超星学习通 TUI 自动化工具）的 Windows 分发 fork。程序本体在
`app/`，同步自 <https://github.com/renxinyileng/CxKitty>（该仓库才是本 fork 的上游，
大模型答题、配置编辑器等改动都在那边先落地）；本 fork 额外提供各平台的环境准备脚本、CI 与启动器。

Python 运行时**不入库**，由 `scripts/setup-*` 按需下载：

| 目录 | 内容 | 是否入库 |
|---|---|---|
| `app/` | 程序本体（`main.py` / `config_editor.py` / `cxapi` / `resolver` / `pyproject.toml` / `config.yml`） | 是 |
| `scripts/` | 各平台环境准备脚本 + `check_env.py` + `smoke_test.py` | 是 |
| `runtime/` | Windows 嵌入式 Python（setup-windows.ps1 下载解压） | 否 |
| `.venv/` | Linux/macOS 虚拟环境 | 否 |

## 常用命令

```bash
# 准备环境（可重复执行；--force 重建）
./scripts/setup-linux.sh
./scripts/setup-macos.sh
.\scripts\setup-windows.ps1          # 或双击 scripts\setup-windows.bat

# 换镜像源（默认走 requirements.txt 里的清华源）
./scripts/setup-linux.sh --index-url https://pypi.org/simple

# 运行
./启动.sh                                  # Linux/macOS（菜单；缺环境只提示）
cd app && ../.venv/bin/python main.py     # 或直接跑
启动.bat                                   # Windows（菜单；缺环境自动装/补装）

# 环境是否完整（启动器与安装脚本共用同一判断）
./.venv/bin/python scripts/check_env.py

# 可视化改配置（保留 config.yml 注释，覆盖前备份为 config.yml.bak）
cd app && ../.venv/bin/python main.py --config

# 唯一的测试：离线冒烟测试（不访问超星接口）
./.venv/bin/python scripts/smoke_test.py
.\runtime\python.exe .\scripts\smoke_test.py

# 格式化（dev 依赖，line-length = 100）
cd app && poetry run black . && poetry run isort .

# Docker
docker build --tag cx-kitty app/
```

仓库没有 pytest/unittest，`scripts/smoke_test.py` 是唯一的自动化验证，覆盖模块导入、
验证码识别链路、滑块验证码定位、人脸上传组包、题目 HTML 解析、试题导出、TUI 渲染、终端二维码、
配置编辑器读写、大模型答题器（请求打桩，不出网）、搜索器调度策略，以及
"`config.yml` 注释里出现的搜索器都已在 `SEARCHERS` 字典注册"。

## 架构

### 两层划分

- **`app/cxapi/`** — 协议层。把超星接口封装成 Dto 对象，只负责取数据/提交，不碰 UI。
- **`app/resolver/`** — 驱动层。消费 Dto 对象跑完自动化流程，同时负责 TUI 渲染。
- **`app/main.py`** — 装配层。建 `rich` 的 `Layout`/`Live`，把 resolver 塞进布局槽位。

### 三个需要读多个文件才能看懂的关键点

**1. `SessionWraper` 会递归重发请求**（`cxapi/session.py`）

它继承 `requests.Session` 并覆写 `request()`：每个响应都过一遍 `get_special_type()`，
识别出验证码页或人脸识别页时先处理掉，**然后递归重发原请求**。所以所有 `cxapi` 里的
接口调用都天然带风控处理，调用方看不到这一层。改动 `request()` 时注意递归深度和重试计数
（`__request_retry_cnt`）的复位时机。

**2. `PointWorkDto` 和 `ExamDto` 实现同一套迭代协议**（`cxapi/base.py`）

`QAQDtoBase` 定义了 `__iter__` / `__next__` / `submit` / `final_submit` / `fallback_save`，
章节测验和课程考试各自实现。因此 `QuestionResolver` 用同一段代码就能驱动两者——
`for index, question in self.exam_dto` 这一行既能跑作业也能跑考试。新增题目来源时实现这套
trait 即可，不用改 resolver。

注意二者语义有差别：作业的 `submit()` 只写本地缓存、`final_submit()` 才真正提交整卷；
考试的 `submit()` 每题都发请求，且会从响应里更新风控参数（`enc` / `encRemainTime` /
`encLastUpdateTime`），漏掉更新后续请求就会失败。

**3. resolver 本身是 rich 渲染对象**

每个 resolver 都实现 `__rich_console__` 并 `yield self.tui_ctx`（一个 `Layout`）。
`main.py` 直接 `lay_left.update(resolver)`，之后 resolver 内部改自己的 `tui_ctx`，
`Live` 就会自动重绘。所以不要在 resolver 里直接 `console.print`。

### 搜索器是配置驱动的

`config.yml` 的 `searchers` 是一个列表，每项用 `type` 指定类名。
`resolver/question.py` 的 `load_searcher()` 把 `type` 首字母大写后去 `SEARCHERS` 字典里查类，
再把该项其余键当 kwargs 展开构造。**新增搜索器必须同时改 `SEARCHERS` 字典和 `config.yml` 注释**，
否则配置里写了名字也会抛 `AttributeError`（冒烟测试的"搜索器注册表"一项就是卡这个的）。

搜索器分两组：`SearcherBase.IS_AI` 为假的进题库组，为真的（`resolver/searcher/llm/` 下的
大模型答题器）进 AI 组。`MultiSearcherWraper` 按 `config.yml` 的 `searcher_policy` 调度：
先并行请求题库组，题库出了**能和本题选项对上**的答案就直接返回、完全不请求 AI；否则并行请求
AI 组，把各家答案归一化后投票，达到 `ai_min_votes` 的排到最前并标注 `共识 n/m`。
新增服务商在 `resolver/searcher/llm/` 下加一个文件（只声明 `BASE_URL` / 默认模型 / 思考参数），
公共的重试、降级、答案归一化在 `base.py` 与 `answer.py`。

### 配置编辑器是独立入口

`config_editor.py` 用 `ruamel.yaml` 往返读写 `config.yml`（**保留注释与格式**），
`main.py` 在 `import config` **之前**就处理 `--config`/`-c`——因为 `config.py` 在 import 期
就会读配置，配置写坏时正是最需要打开编辑器的时候。改 `main.py` 顶部时别把这段挪到 import 之后。

## 容易踩的坑

**必须以 `app/` 为工作目录运行。** `config.py` 用相对路径读 `config.yml`，
`utils.__version__` 直接把 `pyproject.toml` 当文本切 `version = ` 取值。cwd 不对会
`FileNotFoundError`，或 `Path(None)` 抛 `TypeError`。改 `pyproject.toml` 时别在
`[project] version` 之前插入任何含 `version = ` 的行。

**两个启动器的策略是不对称的, 这是刻意的。** `启动.bat` 在启动前调 `scripts/check_env.py`,
发现运行时缺失或依赖不全就自动跑 `setup-windows.ps1`（解释器在、只缺依赖时该脚本不重下解释器,
只补装依赖）——因为 Windows 全程只用 `runtime\` 下的便携解释器, 装/删都不出仓库目录。
`启动.sh` 用同一个 `check_env.py` 判断, 但**只提示不安装**: Linux/macOS 上装解释器要动系统,
该由用户决定。改环境检测逻辑时只改 `check_env.py`, 三个脚本共用它。

注意 pip 只看 `dist-info` 元数据: 包目录被手工删掉时它认为"已安装"而不会补装, 所以安装脚本
装完还要再跑一次 `check_env.py` 兜底, 不通过就提示 `--force` / `-Force` 重建。

**Windows 嵌入式 Python 的 `._pth` 决定 `sys.path`。** 带 `._pth` 时解释器进 isolated 模式，
脚本所在目录**不会**自动进 `sys.path`。`runtime/` 与 `app/` 分离后，`setup-windows.ps1`
必须往 `python313._pth` 写入 `..\app` 和 `import site`，否则 `import cxapi` 直接失败。

**从上游同步时要保留三处本地改动。** `app/` 的内容整体来自 `renxinyileng/CxKitty`，
但下面几处是本 fork 特有的，覆盖后要重新打上：`main.py` 顶部的 stdout/stderr UTF-8 兜底、
`dialog.py` 的二维码图片（`save_login_qr`，上游没有）、`cxapi/session.py` 与
`cxapi/face_detection.py` 里的 `ndarray.tobytes()`（上游仍在用 numpy 2.0 已移除的 `tostring()`
和直接传 ndarray）。`pyproject.toml` / `poetry.lock` / `requirements.txt` / `Dockerfile` /
`.github/` / `run.bat` 也归本 fork 所有，不要用上游版本覆盖。

**中文输出编码。** Windows 上 stdout 不是真实控制台（被重定向/管道）时会退回 cp1252，
打印中文直接 `UnicodeEncodeError`——连 logo 都出不来。`main.py` 和 `smoke_test.py` 启动时
都会把 stdout/stderr 重配为 UTF-8，启动脚本另外设了 `PYTHONUTF8=1`。新增入口点时记得带上。

**`app/.github/` 下的 workflow 不会执行。** GitHub 只读仓库根目录的 `.github/workflows/`。
`app/.github/` 里那两个是上游的发布流程，处于失效状态。真正生效的是根目录的
`verify-setup.yml`（三平台跑 setup 脚本 + 冒烟测试 + poetry lock 校验 + Docker 构建）。

**`requirements.txt` 是生成物，不要手改。** 依赖变更流程：改 `app/pyproject.toml` →
`poetry lock` → `poetry export -f requirements.txt --output requirements.txt --without-hashes`
（需 `poetry-plugin-export`），两个文件一起提交。CI 有 `poetry check --lock` 会卡住不一致的提交。

**依赖版本受嵌入式解释器约束。** 目标是 `>=3.11,<3.14`，且必须在 win_amd64 上有 wheel。
个别包的 `requires-python` 元数据比实际 wheel 覆盖范围宽（例如 onnxruntime 1.24 声明支持
3.10 但不发 cp310 wheel），升级前用
`pip install --dry-run --only-binary=:all: --platform win_amd64 --python-version 3.13 --abi cp313 -r requirements.txt`
验证。

**Python 版本升级不能只看版本号。** CPython 一个系列进入 security-only 后只发源码、不再出
Windows 嵌入式发行版。`setup-windows.ps1` 因此是从高到低逐个探测哪个补丁版**真的**有
embed zip，而不是取最新版本号。
