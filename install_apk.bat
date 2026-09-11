@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
echo ADB devices:
"%ADB%" devices -l
echo.
echo Connecting to phone...
for /f "tokens=1" %%i in ('"%ADB%" devices ^| findstr /v "List" ^| findstr "device"') do (
    echo Found device: %%i
    "%ADB%" -s %%i install -r "build\app\outputs\flutter-apk\app-debug.apk"
)
