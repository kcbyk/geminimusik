@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" devices >nul
ping -n 3 127.0.0.1 >nul

"%ADB%" shell am start -n com.android.settings/com.android.settings.SubSettings --es :settings:show_fragment com.android.settings.KeyShortcutSettings
