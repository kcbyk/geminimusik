@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" devices >nul
ping -n 3 127.0.0.1 >nul

echo Varsayilan dijital asistan ogesine tiklaniyor...
"%ADB%" shell input tap 500 340
ping -n 2 127.0.0.1 >nul

"%ADB%" shell uiautomator dump /sdcard/view_list.xml
"%ADB%" shell cat /sdcard/view_list.xml | findstr /i "ai_music music hub google"
