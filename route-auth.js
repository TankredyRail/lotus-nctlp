const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const db = require('../db/client');

const JWT_SECRET = process.env.JWT_SECRET || 'lotus-secret';
const JWT_EXPIRES = '7d';

// POST /api/auth/register
router.post('/register', async (req, res) => {
  const { email, password, full_name, inn } = req.body;
  if (!email || !password || !full_name) {
    return res.status(400).json({ error: 'email, password, full_name обязательны' });
  }
  try {
    const hash = await bcrypt.hash(password, 10);
    let org_id = null;
    if (inn) {
      const org = await db.query('SELECT id FROM organizations WHERE inn=$1', [inn]);
      if (org.rows[0]) org_id = org.rows[0].id;
    }
    const { rows } = await db.query(
      `INSERT INTO users (email, password_hash, full_name, organization_id)
       VALUES ($1,$2,$3,$4) RETURNING id, email, full_name, role`,
      [email, hash, full_name, org_id]
    );
    const user = rows[0];
    const token = jwt.sign({ id: user.id, email: user.email, role: user.role }, JWT_SECRET, { expiresIn: JWT_EXPIRES });
    res.status(201).json({ token, user });
  } catch (err) {
    if (err.code === '23505') return res.status(409).json({ error: 'Email уже зарегистрирован' });
    res.status(500).json({ error: err.message });
  }
});

// POST /api/auth/login
router.post('/login', async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) return res.status(400).json({ error: 'email и password обязательны' });
  try {
    const { rows } = await db.query(
      `SELECT u.*, o.short_name as org_name, o.inn
       FROM users u LEFT JOIN organizations o ON o.id = u.organization_id
       WHERE u.email=$1`,
      [email]
    );
    if (!rows[0]) return res.status(401).json({ error: 'Неверный email или пароль' });
    const user = rows[0];
    // Demo mode: allow any password for test users
    let valid = false;
    if (user.password_hash.startsWith('$2b$10$placeholder')) {
      valid = true; // demo users
    } else {
      valid = await bcrypt.compare(password, user.password_hash);
    }
    if (!valid) return res.status(401).json({ error: 'Неверный email или пароль' });
    const token = jwt.sign(
      { id: user.id, email: user.email, role: user.role, org_name: user.org_name },
      JWT_SECRET, { expiresIn: JWT_EXPIRES }
    );
    res.json({ token, user: { id: user.id, email: user.email, full_name: user.full_name, role: user.role, org_name: user.org_name, inn: user.inn } });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/auth/me
router.get('/me', require('../middleware/auth').authMiddleware, async (req, res) => {
  try {
    const { rows } = await db.query(
      `SELECT u.id, u.email, u.full_name, u.role, o.short_name as org_name, o.inn, o.full_name as org_full_name
       FROM users u LEFT JOIN organizations o ON o.id = u.organization_id
       WHERE u.id=$1`,
      [req.user.id]
    );
    if (!rows[0]) return res.status(404).json({ error: 'Пользователь не найден' });
    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
