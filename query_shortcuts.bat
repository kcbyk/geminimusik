@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" devices >nul
ping -n 3 127.0.0.1 >nul

echo === SYSTEM ===
"%ADB%" shell settings list system | findstr "key home assist launch"
echo === SECURE ===
"%ADB%" shell settings list secure | findstr "key home assist launch"
echo === GLOBAL ===
"%ADB%" shell settings list global | findstr "key home assist launch"
