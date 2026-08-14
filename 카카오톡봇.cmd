@echo off
chcp 65001 >nul
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0KakaoRoomScheduler.ps1" %*
if errorlevel 1 pause
