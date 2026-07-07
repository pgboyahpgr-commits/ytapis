@echo off
echo Building ytapis Node.js app...
npx pkg server.js --targets node18-win-x64 --output dist\ytapis-node.exe
if not exist "dist" mkdir dist
xcopy /y public dist\public\
echo Done! exe is at dist\ytapis-node.exe
pause
