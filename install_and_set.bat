@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe

echo Cihazlar kontrol ediliyor...
"%ADB%" devices

echo Baglanti deneniyor (192.168.1.100:39799)...
"%ADB%" connect 192.168.1.100:39799

echo Cihaz listesi:
"%ADB%" devices -l

echo APK yukleniyor...
"%ADB%" install -r "build\app\outputs\flutter-apk\app-debug.apk"

echo Assistant ayarlaniyor...
"%ADB%" shell settings put secure voice_interaction_service com.example.ai_music_hub/.JarvisVoiceInteractionService
"%ADB%" shell settings put secure assistant com.example.ai_music_hub/.JarvisOverlayActivity
echo TAMAM!
