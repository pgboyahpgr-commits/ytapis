import tkinter as tk
from tkinter import ttk, messagebox
import threading
import webbrowser
import io
from urllib.request import urlopen

try:
    from PIL import Image, ImageTk
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

from ytapis.core import _fetch, _extract_json, _parse_search_results, _extract_api_keys, search_continue, VideoResult, SearchResponse

MAX_THUMB_WIDTH = 200
MAX_THUMB_HEIGHT = 112


class YtapisApp:
    def __init__(self, root):
        self.root = root
        self.root.title("ytapis - YouTube Search")
        self.root.geometry("1100x750")
        self.root.minsize(800, 500)
        self.root.configure(bg='#1e1e1e')

        style = ttk.Style()
        style.theme_use('clam')
        style.configure('TFrame', background='#1e1e1e')
        style.configure('TLabel', background='#1e1e1e', foreground='#f1f1f1')
        style.configure('TButton', background='#3ea6ff', foreground='#0f0f0f', borderwidth=0, focusthickness=0,
                        font=('Segoe UI', 10, 'bold'))
        style.map('TButton', background=[('active', '#65b8ff')])
        style.configure('Search.TButton', padding=8)
        style.configure('Header.TLabel', font=('Segoe UI', 18, 'bold'), foreground='#f9d423')
        style.configure('Title.TLabel', font=('Segoe UI', 12, 'bold'), foreground='#f1f1f1')
        style.configure('Author.TLabel', font=('Segoe UI', 10), foreground='#aaa')
        style.configure('Meta.TLabel', font=('Segoe UI', 9), foreground='#888')
        style.configure('Duration.TLabel', font=('Segoe UI', 9, 'bold'), foreground='#fff')
        style.configure('Badge.TLabel', font=('Segoe UI', 8, 'bold'), foreground='#0f0f0f',
                        background='#f9d423')
        style.configure('LiveBadge.TLabel', font=('Segoe UI', 8, 'bold'), foreground='#fff',
                        background='#e04040')
        style.configure('LoadMore.TButton', font=('Segoe UI', 10), padding=4)
        self._images = []

        header = ttk.Label(root, text="ytapis", style='Header.TLabel')
        header.pack(pady=(16, 2))
        ttk.Label(root, text="YouTube Search  |  No API Key Required", style='Status.TLabel').pack(pady=(0, 12))
        style.configure('Status.TLabel', font=('Segoe UI', 9), foreground='#aaa')

        search_frame = ttk.Frame(root)
        search_frame.pack(fill=tk.X, padx=20, pady=(0, 8))
        self.search_entry = ttk.Entry(search_frame, font=('Segoe UI', 12))
        self.search_entry.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(0, 8), ipady=6)
        self.search_entry.bind('<Return>', lambda e: self.do_search())
        self.search_btn = ttk.Button(search_frame, text="Search", style='Search.TButton', command=self.do_search)
        self.search_btn.pack(side=tk.RIGHT)

        self.status_label = ttk.Label(root, text="Enter a query to search YouTube", style='Status.TLabel')
        self.status_label.pack(pady=(0, 6))
        self.progress = ttk.Progressbar(root, mode='indeterminate', length=200)
        self.progress.pack(pady=(0, 8))
        self.progress.pack_forget()

        self.load_more_btn = tk.Button(root, text="Load More...", bg='#2a2a2a', fg='#3ea6ff',
                                       font=('Segoe UI', 10, 'bold'), bd=1, padx=20, pady=6,
                                       cursor='hand2', activebackground='#333',
                                       activeforeground='#65b8ff',
                                       command=self._load_more)
        self.load_more_btn.pack_forget()

        canvas = tk.Canvas(root, bg='#1e1e1e', highlightthickness=0)
        scrollbar = ttk.Scrollbar(root, orient=tk.VERTICAL, command=canvas.yview)
        self.results_frame = ttk.Frame(canvas)
        self.results_frame.bind('<Configure>',
                                lambda e: canvas.configure(scrollregion=canvas.bbox('all')))
        canvas.create_window((0, 0), window=self.results_frame, anchor='nw')
        canvas.configure(yscrollcommand=scrollbar.set)
        canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(20, 0), pady=(0, 16))
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y, pady=(0, 16), padx=(0, 20))
        canvas.bind('<Configure>', lambda e: canvas.itemconfig(1, width=e.width))

        self._continuation = None
        self._api_key = None
        self._context = None
        self._last_query = ''

    def _download_thumbnail(self, url):
        try:
            req = urlopen(
                f"https://wsrv.nl/?url={urlencode_component(url)}&w={MAX_THUMB_WIDTH}&h={MAX_THUMB_HEIGHT}&fit=cover")
            data = req.read()
            image = Image.open(io.BytesIO(data))
            image = image.resize((MAX_THUMB_WIDTH, MAX_THUMB_HEIGHT), Image.LANCZOS)
            return ImageTk.PhotoImage(image)
        except Exception:
            return None

    def do_search(self):
        query = self.search_entry.get().strip()
        if not query:
            return
        self._last_query = query
        self._continuation = None
        self._api_key = None
        self._context = None
        self.search_btn.config(state=tk.DISABLED)
        self.status_label.config(text=f'Searching for "{query}"...')
        self.progress.pack(pady=(0, 8))
        self.progress.start(10)
        self.load_more_btn.pack_forget()
        threading.Thread(target=self._search, args=(query,), daemon=True).start()

    def _search(self, query):
        try:
            html = _fetch(f"https://www.youtube.com/results?search_query={query}")
            data = _extract_json(html, "var ytInitialData")
            if not data:
                self.root.after(0, self._display_results, [], query)
                return
            results, continuation = _parse_search_results(data, 20)
            keys = _extract_api_keys(html)
            self._continuation = continuation
            self._api_key = keys[0]
            self._context = keys[1]
            self.root.after(0, self._display_results, results, query)
        except Exception as e:
            self.root.after(0, self._show_error, str(e))

    def _display_results(self, results, query):
        self.progress.stop()
        self.progress.pack_forget()
        self.search_btn.config(state=tk.NORMAL)
        self._images.clear()
        for w in self.results_frame.winfo_children():
            w.destroy()
        if not results:
            self.status_label.config(text=f'No results for "{query}"')
            self.load_more_btn.pack_forget()
            return
        self._all_results = list(results)
        count = len(results)
        self.status_label.config(text=f'Found {count} results for "{query}"')
        for v in self._all_results:
            self._create_card(self.results_frame, v)
        if self._continuation:
            self.load_more_btn.pack(pady=(8, 4), before=self.progress)
        else:
            self.load_more_btn.pack_forget()

    def _load_more(self):
        if not self._continuation:
            return
        self.load_more_btn.config(state=tk.DISABLED, text="Loading...")
        threading.Thread(target=self._load_more_worker, daemon=True).start()

    def _load_more_worker(self):
        try:
            response = search_continue(
                self._continuation, limit=20,
                api_key=self._api_key, context=self._context, path="search"
            )
            self._continuation = response.continuation
            self.root.after(0, self._append_results, response.results)
        except Exception as e:
            self.root.after(0, self._show_error, str(e))
            self.root.after(0, self._reset_load_btn)

    def _append_results(self, more):
        self._reset_load_btn()
        if not more:
            self.load_more_btn.pack_forget()
            return
        for v in more:
            self._all_results.append(v)
            self._create_card(self.results_frame, v)
        self.status_label.config(text=f'Found {len(self._all_results)} results')
        if not self._continuation:
            self.load_more_btn.pack_forget()

    def _reset_load_btn(self):
        self.load_more_btn.config(state=tk.NORMAL, text="Load More...")
        if not self._continuation:
            self.load_more_btn.pack_forget()

    def _show_error(self, msg):
        self.progress.stop()
        self.progress.pack_forget()
        self.search_btn.config(state=tk.NORMAL)
        self.status_label.config(text=f'Error: {msg}')
        messagebox.showerror("Search Error", msg)

    def _create_card(self, parent, v):
        vid = v.id if isinstance(v, VideoResult) else v.get('id', '')
        title = v.title if isinstance(v, VideoResult) else v.get('title', 'Untitled')
        author = v.author if isinstance(v, VideoResult) else v.get('author', 'Unknown')
        url = v.full_url if isinstance(v, VideoResult) else v.get('fullUrl',
                                                                   f'https://www.youtube.com/watch?v={vid}')
        duration = v.duration if isinstance(v, VideoResult) else v.get('duration', '')
        view_count = v.view_count if isinstance(v, VideoResult) else v.get('viewCount', '')
        published_time = v.published_time if isinstance(v, VideoResult) else v.get('publishedTime', '')
        thumbnail = v.thumbnail if isinstance(v, VideoResult) else v.get('thumbnail', '')
        channel_avatar = v.channel_avatar if isinstance(v, VideoResult) else v.get('channelAvatar', '')
        is_live = v.is_live if isinstance(v, VideoResult) else v.get('isLive', False)
        is_upcoming = v.is_upcoming if isinstance(v, VideoResult) else v.get('isUpcoming', False)
        is_verified = v.is_verified if isinstance(v, VideoResult) else v.get('isVerified', False)

        frame = tk.Frame(parent, bg='#2a2a2a', bd=0, highlightthickness=0, padx=8, pady=8)
        frame.pack(fill=tk.X, padx=4, pady=4)
        frame.bind('<Enter>', lambda e: frame.configure(bg='#333333'))
        frame.bind('<Leave>', lambda e: frame.configure(bg='#2a2a2a'))

        if thumbnail and HAS_PIL:
            img = self._download_thumbnail(thumbnail)
            if img:
                self._images.append(img)
                thumb_label = tk.Label(frame, image=img, bg='#2a2a2a', cursor='hand2')
                thumb_label.image = img
                thumb_label.pack(side=tk.LEFT, padx=(0, 10))
                thumb_label.bind('<Button-1>', lambda e, u=url: webbrowser.open(u))
                thumb_label.bind('<Enter>', lambda e: thumb_label.configure(bg='#333333'))
                thumb_label.bind('<Leave>', lambda e: thumb_label.configure(bg='#2a2a2a'))

        info_frame = tk.Frame(frame, bg='#2a2a2a')
        info_frame.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

        title_row = tk.Frame(info_frame, bg='#2a2a2a')
        title_row.pack(fill=tk.X, anchor=tk.W)

        title_label = tk.Label(title_row, text=title, fg='#f1f1f1', bg='#2a2a2a',
                               font=('Segoe UI', 12, 'bold'), anchor=tk.W, justify=tk.LEFT,
                               wraplength=600)
        title_label.pack(side=tk.LEFT, anchor=tk.W)
        title_label.bind('<Enter>', lambda e: title_label.configure(bg='#333333'))
        title_label.bind('<Leave>', lambda e: title_label.configure(bg='#2a2a2a'))

        if duration:
            dur_bg = '#e04040' if is_live else '#3ea6ff'
            dur_text = "LIVE" if is_live else ("UPCOMING" if is_upcoming else duration)
            dur_label = tk.Label(title_row, text=f" {dur_text} ", fg='#fff', bg=dur_bg,
                                 font=('Segoe UI', 8, 'bold'))
            dur_label.pack(side=tk.RIGHT, padx=(8, 0))

        if is_live or is_upcoming:
            badge_text = "LIVE NOW" if is_live else "UPCOMING"
            badge_color = '#e04040' if is_live else '#f9d423'
            badge_fg = '#fff' if is_live else '#0f0f0f'
            tk.Label(info_frame, text=badge_text, fg=badge_fg, bg=badge_color,
                     font=('Segoe UI', 8, 'bold'), padx=6, pady=1).pack(anchor=tk.W, pady=(2, 0))

        author_row = tk.Frame(info_frame, bg='#2a2a2a')
        author_row.pack(fill=tk.X, anchor=tk.W, pady=(2, 0))

        if channel_avatar and HAS_PIL:
            try:
                req = urlopen(f"https://wsrv.nl/?url={urlencode_component(channel_avatar)}&w=20&h=20&fit=cover")
                av_data = req.read()
                av_img = Image.open(io.BytesIO(av_data))
                av_img = av_img.resize((20, 20), Image.LANCZOS)
                av_tk = ImageTk.PhotoImage(av_img)
                self._images.append(av_tk)
                av_label = tk.Label(author_row, image=av_tk, bg='#2a2a2a')
                av_label.image = av_tk
                av_label.pack(side=tk.LEFT, padx=(0, 4))
            except Exception:
                pass

        author_text = author
        if is_verified:
            author_text += " \u2713"
        author_label = tk.Label(author_row, text=author_text, fg='#aaa' if not is_verified else '#3ea6ff',
                                bg='#2a2a2a', font=('Segoe UI', 10))
        author_label.pack(side=tk.LEFT)
        author_label.bind('<Enter>', lambda e: author_label.configure(bg='#333333'))
        author_label.bind('<Leave>', lambda e: author_label.configure(bg='#2a2a2a'))

        meta_parts = []
        if view_count:
            meta_parts.append(view_count)
        if published_time:
            meta_parts.append(published_time)
        if vid:
            meta_parts.append(vid)
        if meta_parts:
            tk.Label(info_frame, text="  \u2022  ".join(meta_parts), fg='#666', bg='#2a2a2a',
                     font=('Segoe UI', 8)).pack(anchor=tk.W, pady=(2, 0))

        btn_frame = tk.Frame(info_frame, bg='#2a2a2a')
        btn_frame.pack(anchor=tk.W, pady=(6, 0))

        play_btn = tk.Button(btn_frame, text="\u25B6 Play", bg='#ff4d4d', fg='#fff',
                             font=('Segoe UI', 9, 'bold'), bd=0, padx=14, pady=2, cursor='hand2',
                             activebackground='#e04040',
                             command=lambda u=url: webbrowser.open(u))
        play_btn.pack(side=tk.LEFT, padx=(0, 6))
        play_btn.bind('<Enter>', lambda e: play_btn.configure(bg='#e04040'))
        play_btn.bind('<Leave>', lambda e: play_btn.configure(bg='#ff4d4d'))

        info_btn = tk.Button(btn_frame, text="Info", bg='#444', fg='#ccc',
                             font=('Segoe UI', 9), bd=0, padx=12, pady=2, cursor='hand2',
                             activebackground='#555',
                             command=lambda v=v: self._show_info(v))
        info_btn.pack(side=tk.LEFT)
        info_btn.bind('<Enter>', lambda e: info_btn.configure(bg='#555'))
        info_btn.bind('<Leave>', lambda e: info_btn.configure(bg='#444'))

    def _show_info(self, v):
        vid = v.id if isinstance(v, VideoResult) else v.get('id', '')
        title = v.title if isinstance(v, VideoResult) else v.get('title', 'Untitled')
        author = v.author if isinstance(v, VideoResult) else v.get('author', 'Unknown')
        url = v.full_url if isinstance(v, VideoResult) else v.get('fullUrl',
                                                                   f'https://www.youtube.com/watch?v={vid}')
        duration = v.duration if isinstance(v, VideoResult) else v.get('duration', '')
        view_count = v.view_count if isinstance(v, VideoResult) else v.get('viewCount', '')
        published_time = v.published_time if isinstance(v, VideoResult) else v.get('publishedTime', '')
        description = v.description if isinstance(v, VideoResult) else v.get('description', '')
        is_live = v.is_live if isinstance(v, VideoResult) else v.get('isLive', False)
        is_upcoming = v.is_upcoming if isinstance(v, VideoResult) else v.get('isUpcoming', False)

        win = tk.Toplevel(self.root)
        win.title("Video Info")
        win.geometry("600x520")
        win.configure(bg='#1e1e1e')

        ttk.Label(win, text=title, font=('Segoe UI', 14, 'bold'), foreground='#f1f1f1',
                  background='#1e1e1e', wraplength=560).pack(pady=(16, 4))
        ttk.Label(win, text=f"by {author}", font=('Segoe UI', 10), foreground='#aaa',
                  background='#1e1e1e').pack()

        meta_parts = []
        if duration:
            meta_parts.append(f"Duration: {duration}")
        if view_count:
            meta_parts.append(f"Views: {view_count}")
        if published_time:
            meta_parts.append(f"Published: {published_time}")
        if is_live:
            meta_parts.append("LIVE")
        if is_upcoming:
            meta_parts.append("Upcoming")
        if meta_parts:
            ttk.Label(win, text="  |  ".join(meta_parts), font=('Segoe UI', 9), foreground='#888',
                      background='#1e1e1e').pack(pady=(4, 0))

        ttk.Label(win, text=f"ID: {vid}", font=('Segoe UI', 9), foreground='#666',
                  background='#1e1e1e').pack(pady=(0, 0))

        if description:
            desc_frame = tk.Frame(win, bg='#1e1e1e')
            desc_frame.pack(fill=tk.X, padx=20, pady=(12, 4))
            tk.Label(desc_frame, text="Description:", fg='#aaa', bg='#1e1e1e',
                     font=('Segoe UI', 9, 'bold')).pack(anchor=tk.W)
            desc_text = (description[:300] + '...') if len(description) > 300 else description
            tk.Label(desc_frame, text=desc_text, fg='#888', bg='#1e1e1e',
                     font=('Segoe UI', 9), wraplength=560, justify=tk.LEFT).pack(anchor=tk.W)

        embed_url = f"https://www.youtube.com/embed/{vid}?autoplay=1&rel=0"
        ttk.Label(win, text="\nClick below to play in your browser:", font=('Segoe UI', 9), foreground='#aaa',
                  background='#1e1e1e').pack(pady=(8, 4))
        play_link = tk.Button(win, text=f"\u25B6 Play: {title[:50]}",
                              bg='#ff4d4d', fg='#fff',
                              font=('Segoe UI', 10, 'bold'), bd=0, padx=16, pady=6,
                              cursor='hand2', activebackground='#e04040',
                              command=lambda u=url: webbrowser.open(u))
        play_link.pack(pady=6)
        play_link.bind('<Enter>', lambda e: play_link.configure(bg='#e04040'))
        play_link.bind('<Leave>', lambda e: play_link.configure(bg='#ff4d4d'))
        tk.Button(win, text="Close", bg='#444', fg='#ccc', font=('Segoe UI', 9),
                  bd=0, padx=12, pady=2, command=win.destroy).pack(pady=(12, 0))


def urlencode_component(s):
    from urllib.parse import quote
    return quote(s, safe='')


def main():
    root = tk.Tk()
    YtapisApp(root)
    root.mainloop()


if __name__ == '__main__':
    main()
