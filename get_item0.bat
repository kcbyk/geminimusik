@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" shell cat /sdcard/view.xml | findstr /i "Varsay?lan asistan dijital"
