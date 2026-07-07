@echo off
cd /d "%~dp0"
echo Building ytapis Flutter desktop app...
call flutter build windows --release
echo Done! exe is at build\windows\x64\runner\Release\ytapis_desktop.exe
pause
