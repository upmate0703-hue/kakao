@echo off
chcp 65001 > nul
title 카카오 발송기 - 필수 요소 확인
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0필수요소.ps1"