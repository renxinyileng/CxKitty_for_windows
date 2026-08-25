@echo off
chcp 65001 >nul
rem 启用 UTF-8 模式, 否则输出被重定向到文件/管道时打印中文会 UnicodeEncodeError
set PYTHONUTF8=1
cd /d "%~dp0"
set "blank=0"

rem 首次运行 (或依赖被删/上次装到一半) 时自动准备环境
call :ensure_env
if errorlevel 1 exit /b 1

:menu
echo ============================================
echo  CxKitty  超星学习通答题姬
echo ============================================
echo  [1] 启动程序
echo  [2] 配置编辑器 (改 app\config.yml: 题库、大模型答题等)
echo  [3] 环境自检 (离线冒烟测试, 不访问超星接口)
echo  [4] 重装运行时与依赖
echo  [0] 退出
echo.
set "sel="
set /p "sel=请输入序号后回车 (直接回车即启动程序): "
echo.
if not defined sel goto blank
set "blank=0"
goto dispatch

:blank
rem 无输入: 首次按启动程序处理; 连续两次则退出, 免得以管道/重定向方式运行时在菜单里空转
set /a blank+=1
if %blank% geq 2 exit /b 0
set "sel=1"

:dispatch
if "%sel%"=="1" goto run
if "%sel%"=="2" goto config
if "%sel%"=="3" goto selftest
if "%sel%"=="4" goto reinstall
if "%sel%"=="0" exit /b 0
echo 无效的选项: %sel%
echo.
goto menu

:run
rem 必须以 app\ 为工作目录: config.yml / pyproject.toml 都是按相对路径读取的
cd app
..\runtime\python.exe main.py
set "code=%errorlevel%"
cd ..
echo.
echo 程序已退出 (返回码 %code%)
goto again

:config
rem 配置编辑器: 交互式修改 config.yml, 保留原有注释, 覆盖前自动备份为 config.yml.bak
cd app
..\runtime\python.exe main.py --config
cd ..
goto again

:selftest
runtime\python.exe scripts\smoke_test.py
goto again

:reinstall
call :setup -Force
goto again

:again
echo.
pause
echo.
goto menu

:ensure_env
rem 检测 Python 环境, 缺什么就自动补什么。windows 上只用 runtime\ 下的便携
rem (嵌入式) 解释器, 不去碰系统里已装的 Python, 所以这里只认这一个位置。
if not exist "runtime\python.exe" (
    echo 未检测到 Python 运行时, 开始自动准备环境...
    echo.
    call :setup
    if errorlevel 1 exit /b 1
    echo.
    exit /b 0
)
rem 解释器在, 再确认依赖齐全 (scripts\check_env.py 只查不导入, 很快)
runtime\python.exe scripts\check_env.py
if errorlevel 1 (
    echo.
    echo 运行环境不完整, 开始自动补装依赖...
    echo.
    call :setup
    if errorlevel 1 exit /b 1
    echo.
)
exit /b 0

:setup
rem 调用环境准备脚本, 参数原样透传 (如 -Force)
powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\setup-windows.ps1" %*
if errorlevel 1 (
    echo.
    echo 环境准备失败, 请查看上面的报错信息。
    pause
    exit /b 1
)
exit /b 0
