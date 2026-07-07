from flask import Flask, render_template, jsonify, request
from ytapis import search

app = Flask(__name__)

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
    app.run(host='0.0.0.0', port=5000, debug=True)
