@echo off
rem Installs the Android SDK packages that Godot 4.7.2 needs to build the Quest APK.
rem Versions come from Godot 4.7.2's platform/android/java/app/config.gradle.
rem Expects:  %LOCALAPPDATA%\Android\jdk-17                     (JDK 17)
rem           %LOCALAPPDATA%\Android\Sdk\cmdline-tools\latest   (Android command-line tools)
rem The tool shows the Android SDK terms (https://developer.android.com/studio/terms).
setlocal
set "JAVA_HOME=%LOCALAPPDATA%\Android\jdk-17"
set "SDK=%LOCALAPPDATA%\Android\Sdk"
set "MGR=%SDK%\cmdline-tools\latest\bin\sdkmanager.bat"
if not exist "%JAVA_HOME%\bin\java.exe" (echo JDK 17 not found in %JAVA_HOME% & exit /b 1)
if not exist "%MGR%" (echo Android command-line tools not found in %SDK% & exit /b 1)

rem Needed for the export itself.
call "%MGR%" --sdk_root="%SDK%" "platform-tools" "build-tools;36.1.0" "platforms;android-36"
if errorlevel 1 (echo. & echo sdkmanager FAILED on the required packages & exit /b 1)
echo.
echo REQUIRED PACKAGES OK

rem Listed in the Godot docs as well; large (the NDK is about 700 MB). The export works without them.
call "%MGR%" --sdk_root="%SDK%" "cmake;3.22.1" "ndk;29.0.14206865"
if errorlevel 1 (echo. & echo NDK / CMake not installed. Run this file again later to retry. & exit /b 2)
echo.
echo ALL PACKAGES OK in %SDK%
endlocal
