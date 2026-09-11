@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" devices >nul
ping -n 3 127.0.0.1 >nul

"%ADB%" shell settings put secure assistant com.example.ai_music_hub/.JarvisOverlayActivity
"%ADB%" shell settings put secure voice_interaction_service com.example.ai_music_hub/.JarvisVoiceInteractionService
"%ADB%" shell settings put system long_press_home_key launch_google_search

echo Simulating KEYCODE_ASSIST...
"%ADB%" shell input keyevent 219

ping -n 2 127.0.0.1 >nul
echo Current focus:
"%ADB%" shell dumpsys window | findstr "mCurrentFocus"
