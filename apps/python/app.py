import tkinter as tk
from tkinter import ttk, messagebox
import threading
import webbrowser
from ytapis import search

class YtapisApp:
    def __init__(self, root):
        self.root = root
        self.root.title("ytapis - YouTube Search")
        self.root.geometry("900x650")
        self.root.minsize(600, 400)
        self.root.configure(bg='#1e1e1e')

        style = ttk.Style()
        style.theme_use('clam')
        style.configure('TFrame', background='#1e1e1e')
        style.configure('TLabel', background='#1e1e1e', foreground='#f1f1f1')
        style.configure('TButton', background='#3ea6ff', foreground='#0f0f0f', borderwidth=0, focusthickness=0, font=('Segoe UI', 10, 'bold'))
        style.map('TButton', background=[('active', '#65b8ff')])
        style.configure('Search.TButton', padding=8)
        style.configure('Header.TLabel', font=('Segoe UI', 18, 'bold'), foreground='#f9d423')
        style.configure('Title.TLabel', font=('Segoe UI', 11, 'bold'), foreground='#f1f1f1', wraplength=300)
        style.configure('Author.TLabel', font=('Segoe UI', 9), foreground='#888')
        style.configure('Status.TLabel', font=('Segoe UI', 9), foreground='#aaa')
        style.configure('Stats.TLabel', font=('Segoe UI', 9), foreground='#3ea6ff')

        header = ttk.Label(root, text="ytapis", style='Header.TLabel')
        header.pack(pady=(16, 2))

        sub = ttk.Label(root, text="YouTube Search  |  No API Key Required", style='Status.TLabel')
        sub.pack(pady=(0, 12))

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

        canvas = tk.Canvas(root, bg='#1e1e1e', highlightthickness=0)
        scrollbar = ttk.Scrollbar(root, orient=tk.VERTICAL, command=canvas.yview)
        self.results_frame = ttk.Frame(canvas)
        self.results_frame.bind('<Configure>', lambda e: canvas.configure(scrollregion=canvas.bbox('all')))
        canvas.create_window((0, 0), window=self.results_frame, anchor='nw')
        canvas.configure(yscrollcommand=scrollbar.set)
        canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(20, 0), pady=(0, 16))
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y, pady=(0, 16), padx=(0, 20))
        canvas.bind('<Configure>', lambda e: canvas.itemconfig(1, width=e.width))

    def do_search(self):
        query = self.search_entry.get().strip()
        if not query:
            return
        self.search_btn.config(state=tk.DISABLED)
        self.status_label.config(text=f'Searching for "{query}"...')
        self.progress.pack(pady=(0, 8))
        self.progress.start(10)
        threading.Thread(target=self._search, args=(query,), daemon=True).start()

    def _search(self, query):
        try:
            results = search(query, limit=15)
            self.root.after(0, self._display_results, results, query)
        except Exception as e:
            self.root.after(0, self._show_error, str(e))

    def _display_results(self, results, query):
        self.progress.stop()
        self.progress.pack_forget()
        self.search_btn.config(state=tk.NORMAL)
        for w in self.results_frame.winfo_children():
            w.destroy()
        if not results:
            self.status_label.config(text=f'No results for "{query}"')
            return
        self.status_label.config(text=f'Found {len(results)} results for "{query}"')
        for v in results:
            self._create_card(self.results_frame, v)

    def _show_error(self, msg):
        self.progress.stop()
        self.progress.pack_forget()
        self.search_btn.config(state=tk.NORMAL)
        self.status_label.config(text=f'Error: {msg}')
        messagebox.showerror("Search Error", msg)

    def _create_card(self, parent, v):
        frame = tk.Frame(parent, bg='#2a2a2a', bd=0, highlightthickness=0, padx=10, pady=10)
        frame.pack(fill=tk.X, padx=4, pady=4)
        frame.bind('<Enter>', lambda e: frame.configure(bg='#333333'))
        frame.bind('<Leave>', lambda e: frame.configure(bg='#2a2a2a'))

        title = v.get('title', 'Untitled')
        author = v.get('author', 'Unknown')
        vid = v.get('id', '')
        url = v.get('fullUrl', f'https://www.youtube.com/watch?v={vid}')

        ttk.Label(frame, text=title, style='Title.TLabel').pack(anchor=tk.W)
        ttk.Label(frame, text=f'by {author}  |  {vid}', style='Author.TLabel').pack(anchor=tk.W)

        btn_frame = tk.Frame(frame, bg='#2a2a2a')
        btn_frame.pack(anchor=tk.W, pady=(4, 0))
        watch_btn = tk.Button(btn_frame, text="Watch on YouTube", bg='#3ea6ff', fg='#0f0f0f',
                              font=('Segoe UI', 9, 'bold'), bd=0, padx=12, pady=2, cursor='hand2',
                              activebackground='#65b8ff',
                              command=lambda u=url: webbrowser.open(u))
        watch_btn.pack(side=tk.LEFT, padx=(0, 6))
        watch_btn.bind('<Enter>', lambda e: watch_btn.configure(bg='#65b8ff'))
        watch_btn.bind('<Leave>', lambda e: watch_btn.configure(bg='#3ea6ff'))

        thumb_link = f'https://i.ytimg.com/vi/{vid}/hqdefault.jpg'
        thumb_btn = tk.Button(btn_frame, text="View Thumbnail", bg='#444', fg='#ccc',
                              font=('Segoe UI', 9), bd=0, padx=12, pady=2, cursor='hand2',
                              activebackground='#555',
                              command=lambda u=thumb_link: webbrowser.open(u))
        thumb_btn.pack(side=tk.LEFT)
        thumb_btn.bind('<Enter>', lambda e: thumb_btn.configure(bg='#555'))
        thumb_btn.bind('<Leave>', lambda e: thumb_btn.configure(bg='#444'))

def main():
    root = tk.Tk()
    app = YtapisApp(root)
    root.mainloop()

if __name__ == '__main__':
    main()
