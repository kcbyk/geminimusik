@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" start-server >nul
ping -n 5 127.0.0.1 >nul
"%ADB%" devices -l

echo === SECURE SETTINGS ===
"%ADB%" shell settings get secure assistant
"%ADB%" shell settings get secure voice_interaction_service
"%ADB%" shell settings list secure | findstr /i "assist"
echo === BUTTON SHORTCUTS ===
"%ADB%" shell settings list system | findstr /i "press"
"%ADB%" shell settings list secure | findstr /i "press"
