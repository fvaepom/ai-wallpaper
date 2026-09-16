@echo off
rem ai-wallpaper uninstall: rollback all app patches, then delete the tool folder.
rem The .ps1 carries the real work; this wrapper deletes the folder from outside
rem (must be the LAST line: the batch file lives inside the folder it deletes).
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall.ps1"
echo.
echo 按任意键删除工具目录 %~dp0（不想删除请直接关闭本窗口）。
pause >nul
cd /d "%TEMP%"
rd /s /q "%~dp0."
