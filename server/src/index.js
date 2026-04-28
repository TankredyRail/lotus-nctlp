require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');

const app = express();
const PORT = process.env.PORT || 3001;

app.set('trust proxy', 1);
app.use(helmet());

const ALLOWED_ORIGINS = [
  process.env.FRONTEND_URL,
  'https://glowing-moxie-030aea.netlify.app',
  'http://localhost:3000',
  'http://localhost:5173',
  'null',
].filter(Boolean);

app.use(cors({
  origin: (origin, cb) => {
    if (!origin || ALLOWED_ORIGINS.includes(origin)) return cb(null, true);
    cb(new Error('CORS: origin ' + origin + ' не разрешён'));
  },
  methods: ['GET','POST','PATCH','DELETE','OPTIONS'],
  allowedHeaders: ['Content-Type','Authorization'],
  credentials: true,
}));

app.use(express.json({ limit: '2mb' }));

app.use('/api/', rateLimit({ windowMs: 15*60*1000, max: 300, message: { error: 'Too many requests' } }));
app.use('/api/ai/', rateLimit({ windowMs: 60*1000, max: 20, message: { error: 'AI rate limit' } }));

app.use('/api/auth', require('./routes/auth'));
app.use('/api/shipments', require('./routes/shipments'));
app.use('/api/organizations', require('./routes/organizations'));
app.use('/api/ai', require('./routes/ai'));

app.post('/api/admin/migrate', async (req, res) => {
  if (req.headers['x-admin-key'] !== process.env.ADMIN_KEY) {
    return res.status(403).json({ error: 'Forbidden' });
  }
  const fs = require('fs');
  const path = require('path');
  const db = require('./db/client');
  try {
    await db.query("CREATE SEQUENCE IF NOT EXISTS cpp_sequence START 1");
    const schema = fs.readFileSync(path.join(__dirname, '../../db/schema.sql'), 'utf8');
    const statements = schema.split(';').filter(s => s.trim());
    const results = [];
    for (const stmt of statements) {
      if (!stmt.trim()) continue;
      try {
        await db.query(stmt);
        results.push({ ok: true, stmt: stmt.trim().slice(0, 60) });
      } catch (e) {
        results.push({ ok: false, err: e.message, stmt: stmt.trim().slice(0, 60) });
      }
    }
    res.json({ migrated: true, results: results.slice(0, 30) });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/health', (req, res) => {
  res.json({ status: 'ok', version: '1.0.0', app: 'LOTUS НЦТЛП', timestamp: new Date().toISOString() });
});

app.use((req, res) => res.status(404).json({ error: req.method + ' ' + req.path + ' не найден' }));
app.use((err, req, res, next) => {
  console.error('[ERROR]', err.message);
  res.status(500).json({ error: 'Внутренняя ошибка сервера' });
});

app.listen(PORT, () => {
  console.log('✅ LOTUS API запущен на порту ' + PORT);
});

module.exports = app;
