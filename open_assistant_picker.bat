@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" devices >nul
ping -n 3 127.0.0.1 >nul

echo Asistan secim diyalogu aciliyor...
"%ADB%" shell am start -a android.intent.action.MANAGE_DEFAULT_APP --es android.intent.extra.ROLE_NAME android.app.role.ASSISTANT
