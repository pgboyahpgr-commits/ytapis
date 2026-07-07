@echo off
cd /d "%~dp0"
echo Building ytapis Electron app...
call npm install 2>nul
npx electron-builder --win portable
echo Done! exe is at dist\ytapis-search*.exe
pause
