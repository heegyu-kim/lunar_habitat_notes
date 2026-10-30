@echo off
rem Quick check: is the Quest headset microphone delivering sound to Windows at all?
rem Uses ffmpeg directly (no Godot). Wear the headset, make sure Quest Link is connected, then run this.
cd /d "%~dp0"
if not exist ffmpeg.exe (
  echo ffmpeg.exe not found in this folder. See README.txt
  pause
  exit /b 1
)
echo.
echo Audio input devices seen by Windows/ffmpeg:
ffmpeg.exe -hide_banner -list_devices true -f dshow -i dummy 2>&1 | findstr /C:"(audio)"
echo.
echo Recording 5 seconds from "Headset Microphone(Oculus Virtual Audio Device)". Speak now...
ffmpeg.exe -y -hide_banner -loglevel error -f dshow -i "audio=Headset Microphone(Oculus Virtual Audio Device)" -t 5 "%TEMP%\quest_mic_check.wav"
if errorlevel 1 (
  echo Could not open the Quest microphone. Is Quest Link connected?
  pause
  exit /b 1
)
echo.
ffmpeg.exe -hide_banner -i "%TEMP%\quest_mic_check.wav" -af volumedetect -f null - 2>&1 | findstr /C:"max_volume" /C:"mean_volume"
echo.
echo   max_volume around -30 dB or louder  = sound is arriving, the app will record it
echo   max_volume around -90 dB            = Windows receives silence from the headset:
echo                                         restart Quest Link (Link app ^> Settings ^> Beta ^> Restart Oculus),
echo                                         re-wear the headset, check the Quest quick-settings mic mute.
echo.
pause
