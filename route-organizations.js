// organizations.js
const express = require('express');
const router = express.Router();
const db = require('../db/client');

router.get('/', async (req, res) => {
  try {
    const { role } = req.query;
    let q = 'SELECT * FROM organizations';
    const params = [];
    if (role) { q += ' WHERE $1=ANY(role)'; params.push(role); }
    q += ' ORDER BY full_name';
    const { rows } = await db.query(q, params);
    res.json(rows);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

router.get('/:inn', async (req, res) => {
  try {
    const { rows } = await db.query('SELECT * FROM organizations WHERE inn=$1', [req.params.inn]);
    if (!rows[0]) return res.status(404).json({ error: 'Не найдено' });
    res.json(rows[0]);
  } catch (err) { res.status(500).json({ error: err.message }); }
});

router.post('/', async (req, res) => {
  const { inn, full_name, short_name, kpp, ogrn, legal_address, phone, email, role = [] } = req.body;
  if (!inn || !full_name) return res.status(400).json({ error: 'inn и full_name обязательны' });
  try {
    const { rows } = await db.query(
      `INSERT INTO organizations (inn,full_name,short_name,kpp,ogrn,legal_address,phone,email,role)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`,
      [inn,full_name,short_name||full_name,kpp,ogrn,legal_address,phone,email,role]
    );
    res.status(201).json(rows[0]);
  } catch (err) {
    if (err.code==='23505') return res.status(409).json({ error: 'ИНН уже существует' });
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
