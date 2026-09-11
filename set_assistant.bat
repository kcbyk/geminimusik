@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe

echo Baglaniyor...
"%ADB%" connect 192.168.1.100:39799

echo Cihazlar:
"%ADB%" devices

echo Jarvis varsayilan asistan yapiliyor...
"%ADB%" shell settings put secure voice_interaction_service com.example.ai_music_hub/.JarvisVoiceInteractionService
"%ADB%" shell settings put secure assistant com.example.ai_music_hub/.MainActivity

echo Dogrulama:
"%ADB%" shell settings get secure voice_interaction_service
"%ADB%" shell settings get secure assistant
echo TAMAM!
