@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" devices >nul
ping -n 3 127.0.0.1 >nul

echo Ana ekrana donuluyor...
"%ADB%" shell input keyevent 3
ping -n 2 127.0.0.1 >nul

echo Home tusuna uzun basma simule ediliyor (KEYCODE_HOME longpress)...
"%ADB%" shell input keyevent --longpress 3
ping -n 2 127.0.0.1 >nul

echo Aktif pencere:
"%ADB%" shell dumpsys window | findstr "mCurrentFocus"
