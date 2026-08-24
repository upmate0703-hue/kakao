@echo off
chcp 65001 > nul
title KakaoSender - Check
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0prereq.ps1"
if errorlevel 1 (
  echo.
  echo [!] Could not run the checker. Press any key to close.
  pause > nul
)
