@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" devices >nul
ping -n 3 127.0.0.1 >nul

echo Granting permissions...
"%ADB%" shell pm grant com.example.ai_music_hub android.permission.SYSTEM_ALERT_WINDOW
"%ADB%" shell appops set com.example.ai_music_hub SYSTEM_ALERT_WINDOW allow
echo AppOps done!
