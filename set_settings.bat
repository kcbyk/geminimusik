@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" devices >nul
ping -n 3 127.0.0.1 >nul

echo Setting assistant...
"%ADB%" shell settings put secure voice_interaction_service com.example.ai_music_hub/.JarvisVoiceInteractionService
"%ADB%" shell settings put secure assistant com.example.ai_music_hub/.MainActivity

echo Verifying...
"%ADB%" shell settings get secure voice_interaction_service
"%ADB%" shell settings get secure assistant
