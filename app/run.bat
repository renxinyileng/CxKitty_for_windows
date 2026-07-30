@echo off
chcp 65001 >nul
rem 直接运行程序, 要求 ..\runtime 已由 scripts\setup-windows.ps1 准备好
rem 想要"没装就自动装", 请改用仓库根目录的 启动.bat
cd /d "%~dp0"
if not exist "..\runtime\python.exe" (
    echo 未找到 ..\runtime\python.exe, 请先运行仓库根目录的 启动.bat 或 scripts\setup-windows.bat
    pause
    exit /b 1
)
..\runtime\python.exe main.py
pause
