@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" devices >nul
ping -n 3 127.0.0.1 >nul

"%ADB%" shell logcat -c
"%ADB%" shell cmd role add-role-holder assistant com.example.ai_music_hub
"%ADB%" shell logcat -d | findstr /i "assistant role ai_music"
