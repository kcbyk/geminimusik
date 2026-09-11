@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" devices >nul
ping -n 3 127.0.0.1 >nul

"%ADB%" shell uiautomator dump /sdcard/view.xml
"%ADB%" shell cat /sdcard/view.xml | findstr /i "music hub assistant google"
