import os
import sys
import socket
import threading
import webbrowser
from flask import Flask, render_template, jsonify, request
from ytapis import search

app = Flask(__name__)

def get_port():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(('', 0))
    port = sock.getsockname()[1]
    sock.close()
    return port

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/search')
def api_search():
    q = request.args.get('q', '')
    limit = request.args.get('limit', 15, type=int)
    if not q:
        return jsonify({'error': 'missing query param "q"'}), 400
    try:
        results = search(q, limit=limit)
        return jsonify(results)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    port = get_port()
    url = f'http://localhost:{port}'
    threading.Timer(1.0, lambda: webbrowser.open(url)).start()
    print(f'\n  ytapis Python app running at {url}')
    print('  Close this window or press Ctrl+C to stop.\n')
    app.run(host='0.0.0.0', port=port, debug=False)
