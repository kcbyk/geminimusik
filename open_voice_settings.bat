@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" devices >nul
ping -n 3 127.0.0.1 >nul

echo Voice Input Settings aciliyor...
"%ADB%" shell am start -a android.settings.VOICE_INPUT_SETTINGS
