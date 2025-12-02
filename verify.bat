@echo off
setlocal EnableDelayedExpansion

echo ======================================
echo j3kOS Build Verification Tool
echo ======================================
echo.

REM Check if image exists
if not exist j3kOS.img (
    echo [ERROR] j3kOS.img not found!
    echo Run build.bat first.
    exit /b 1
)

REM Run PowerShell verification script
powershell -NoProfile -ExecutionPolicy Bypass -File verify.ps1
exit /b %errorlevel%
