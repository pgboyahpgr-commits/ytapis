# ytapis &mdash; Python Desktop App

Native Windows GUI app for searching YouTube and watching videos. Built with Python tkinter using the `ytapis` PyPI package.

Built and managed by [geethudinoyt](https://github.com/geethudinoyt).

## Features

- Search YouTube with text queries
- Browse results as styled cards with title, author, and video ID
- Click **Play Video** to open and watch in your browser
- Click **Info** for more details

## Run from source

```bash
pip install -r requirements.txt
python app.py
```

## Build .exe

Run `build.bat` or:

```bash
pip install pyinstaller
pyinstaller --noconfirm --onefile --console --hidden-import=ytapis --name "ytapis-python" app.py
```

Output: `dist/ytapis-python.exe` (approx 11 MB)

## Download

Pre-built `.exe` available on the [Releases](https://github.com/pgboyahpgr-commits/ytapis/releases) page.

## License

MIT
