@echo off
chcp 65001 >nul
rem 启用 UTF-8 模式, 否则输出被重定向到文件/管道时打印中文会 UnicodeEncodeError
set PYTHONUTF8=1
cd /d "%~dp0"

rem 首次运行时自动下载 Python 运行时并安装依赖
if not exist "runtime\python.exe" (
    echo 未检测到运行时, 开始自动准备环境...
    echo.
    powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\setup-windows.ps1"
    if errorlevel 1 (
        echo.
        echo 环境准备失败, 请查看上面的报错信息。
        pause
        exit /b 1
    )
    echo.
)

cd app
..\runtime\python.exe main.py
pause
