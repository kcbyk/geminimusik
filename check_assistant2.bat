@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" devices >nul
ping -n 3 127.0.0.1 >nul
"%ADB%" devices -l
echo Voice interaction service:
"%ADB%" shell settings get secure voice_interaction_service
echo Assistant:
"%ADB%" shell settings get secure assistant
