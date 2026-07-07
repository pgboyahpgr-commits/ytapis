@echo off
cd /d "%~dp0"
echo Building ytapis Python desktop app...
python -m PyInstaller --noconfirm --onefile --console --hidden-import=ytapis --name "ytapis-python" app.py
echo Done! exe is at dist\ytapis-python.exe
pause
