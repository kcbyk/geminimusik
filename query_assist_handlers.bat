@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" devices >nul
ping -n 3 127.0.0.1 >nul

echo Assist intentini kimler dinliyor:
"%ADB%" shell pm query-activities -a android.intent.action.ASSIST
