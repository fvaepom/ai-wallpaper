@echo off
rem ai-wallpaper one-click patcher: run install-all.ps1, then deploy shortcuts/uninstall entry.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-all.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy-shortcuts.ps1"
pause
