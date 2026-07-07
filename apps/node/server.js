const express = require('express');
const { search } = require('ytapis-core');
const path = require('path');

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.static(path.join(__dirname, 'public')));

app.get('/search', async (req, res) => {
  const q = req.query.q;
  const limit = parseInt(req.query.limit) || 15;
  if (!q) return res.status(400).json({ error: 'missing query param "q"' });
  try {
    const results = await search(q, { limit });
    res.json(results);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`ytapis Node app running at http://localhost:${PORT}`);
});
