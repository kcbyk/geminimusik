@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" devices >nul
ping -n 3 127.0.0.1 >nul

echo Role holders:
"%ADB%" shell cmd role get-role-holders assistant

echo Setting assistant role to com.example.ai_music_hub...
"%ADB%" shell cmd role add-role-holder assistant com.example.ai_music_hub 2
"%ADB%" shell cmd role set-bidi-default-assistant com.example.ai_music_hub 2

echo Role holders after:
"%ADB%" shell cmd role get-role-holders assistant
