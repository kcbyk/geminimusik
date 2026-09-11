@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" devices >nul
ping -n 3 127.0.0.1 >nul

echo === SECURE SETTINGS ===
"%ADB%" shell settings get secure assistant
"%ADB%" shell settings get secure voice_interaction_service
"%ADB%" shell settings get secure voice_recognition_service

echo === SYSTEM / MIUI SHORTCUTS ===
"%ADB%" shell settings get system key_long_press_home
"%ADB%" shell settings get system long_press_home_key
"%ADB%" shell settings get secure long_press_home_key
"%ADB%" shell settings list secure | findstr /i "assist"
"%ADB%" shell settings list system | findstr /i "home"
