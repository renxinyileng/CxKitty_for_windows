@echo off
chcp 65001 >nul
rem 给不想开 PowerShell 的人用的双击入口, 参数会原样透传给 setup-windows.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-windows.ps1" %*
if errorlevel 1 (
    echo.
    echo 环境准备失败, 请查看上面的报错信息。
)
pause
