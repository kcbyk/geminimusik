@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" devices >nul
ping -n 3 127.0.0.1 >nul

echo Navigasyon modu:
"%ADB%" shell settings get global force_fsg_nav_bar
echo Power tusu ile asistan:
"%ADB%" shell settings get system long_press_power_key
echo Home tusu ile asistan:
"%ADB%" shell settings get system long_press_home_key
