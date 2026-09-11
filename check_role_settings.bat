@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" devices >nul
ping -n 3 127.0.0.1 >nul

echo Assistant:
"%ADB%" shell settings get secure assistant
echo Voice Interaction:
"%ADB%" shell settings get secure voice_interaction_service
