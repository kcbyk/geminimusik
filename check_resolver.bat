@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" devices >nul
ping -n 3 127.0.0.1 >nul

"%ADB%" shell dumpsys activity top | findstr /i "ai_music_hub resolver google"
