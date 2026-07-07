@echo off
echo Building ytapis Python app...
pyinstaller --noconfirm --onefile --console --add-data "templates;templates" --name "ytapis-python" app.py
echo Done! exe is at dist\ytapis-python.exe
pause
