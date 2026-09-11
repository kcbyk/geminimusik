@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" devices >nul
ping -n 3 127.0.0.1 >nul

echo JarvisOverlayActivity baslatiliyor...
"%ADB%" shell am start -n com.example.ai_music_hub/.JarvisOverlayActivity
