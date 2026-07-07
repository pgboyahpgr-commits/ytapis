@echo off
echo Building ytapis Go app...
cd /d "%~dp0"
go build -o dist\ytapis-go.exe -ldflags="-s -w" -trimpath main.go
echo Done! exe is at dist\ytapis-go.exe
pause
