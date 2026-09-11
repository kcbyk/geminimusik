@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" devices >nul
ping -n 3 127.0.0.1 >nul

"%ADB%" shell uiautomator dump /sdcard/shortcuts.xml
"%ADB%" shell cat /sdcard/shortcuts.xml | findstr "text="
