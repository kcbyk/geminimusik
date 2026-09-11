@echo off
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
"%ADB%" devices >nul
ping -n 3 127.0.0.1 >nul

echo 1. APK yukleniyor...
"%ADB%" install -r "build\app\outputs\flutter-apk\app-debug.apk"

echo 2. Asistan servisi baglaniyor...
"%ADB%" shell settings put secure voice_interaction_service com.example.ai_music_hub/.JarvisVoiceInteractionService
"%ADB%" shell settings put secure assistant com.example.ai_music_hub/.JarvisOverlayActivity
"%ADB%" shell settings put system long_press_home_key launch_google_search

echo 3. Izinler veriliyor...
"%ADB%" shell pm grant com.example.ai_music_hub android.permission.SYSTEM_ALERT_WINDOW
"%ADB%" shell appops set com.example.ai_music_hub SYSTEM_ALERT_WINDOW allow
"%ADB%" shell appops set com.example.ai_music_hub 10021 allow

echo 4. Dogrulama:
"%ADB%" shell settings get secure voice_interaction_service
"%ADB%" shell settings get secure assistant
"%ADB%" shell settings get system long_press_home_key
echo BITTI!
