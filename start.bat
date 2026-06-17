@echo off
chcp 65001 >nul 2>&1
title giffgaff eSIM 环境一键配置工具

echo.
echo   ============================================
echo     giffgaff eSIM 环境一键配置工具 v2.0
echo     MuMu 5 + Kitsune Mask + LSPosed + HookEuicc
echo   ============================================
echo.

powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0setup-giffgaff-env.ps1" %*

echo.
echo   ============================================
echo   脚本执行完毕，按任意键退出...
pause >nul
