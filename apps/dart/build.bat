@echo off
echo Building ytapis Dart app...
cd /d "%~dp0"
dart compile exe server.dart -o dist\ytapis-dart.exe
echo Done! exe is at dist\ytapis-dart.exe
pause
