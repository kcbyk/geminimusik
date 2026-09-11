@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" devices >nul
ping -n 3 127.0.0.1 >nul

"%ADB%" shell cmd role add-role-holder android.app.role.ASSISTANT com.example.ai_music_hub
echo Role holders:
"%ADB%" shell cmd role get-role-holders android.app.role.ASSISTANT
