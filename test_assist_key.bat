@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" devices >nul
ping -n 3 127.0.0.1 >nul

echo 1. KEYCODE_ASSIST gonderiliyor (Home uzun basma kodu)...
"%ADB%" shell input keyevent 219

ping -n 2 127.0.0.1 >nul
echo 2. Aktif pencere:
"%ADB%" shell dumpsys window | findstr "mCurrentFocus"
