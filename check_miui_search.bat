@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" devices >nul
ping -n 3 127.0.0.1 >nul

"%ADB%" shell dumpsys activity top | findstr /i "miui"
"%ADB%" shell settings list system | findstr /i "google_search"
'%ADB%' shell settings list secure | findstr /i "google_search"
