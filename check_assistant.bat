@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
echo Assistant Durumu:
"%ADB%" shell settings get secure voice_interaction_service
"%ADB%" shell settings get secure assistant
