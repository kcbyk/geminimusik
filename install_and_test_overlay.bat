@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" devices >nul
ping -n 3 127.0.0.1 >nul

echo Cihaza yukleniyor...
"%ADB%" install -r "build\app\outputs\flutter-apk\app-debug.apk"

echo Asistan ayarlari uygulaniyor...
"%ADB%" shell settings put secure voice_interaction_service com.example.ai_music_hub/.JarvisVoiceInteractionService
"%ADB%" shell settings put secure assistant com.example.ai_music_hub/.JarvisOverlayActivity
"%ADB%" shell pm grant com.example.ai_music_hub android.permission.SYSTEM_ALERT_WINDOW
"%ADB%" shell appops set com.example.ai_music_hub SYSTEM_ALERT_WINDOW allow

echo Test acilisi yapiliyor...
"%ADB%" shell am start -n com.example.ai_music_hub/.JarvisOverlayActivity
echo BITTI!
