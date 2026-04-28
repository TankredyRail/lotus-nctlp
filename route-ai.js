const express = require('express');
const router = express.Router();
const Anthropic = require('@anthropic-ai/sdk');
const db = require('../db/client');

const getClient = () => new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

// POST /api/ai/chat
router.post('/chat', async (req, res) => {
  if (!process.env.ANTHROPIC_API_KEY) return res.status(503).json({ error: 'ANTHROPIC_API_KEY не настроен' });
  const { messages } = req.body;
  if (!Array.isArray(messages)) return res.status(400).json({ error: 'messages обязательны' });

  try {
    // Get platform stats
    const stats = await db.query(`
      SELECT
        COUNT(*) as total_shipments,
        COUNT(*) FILTER (WHERE status='active') as active,
        COUNT(*) FILTER (WHERE status='completed') as completed,
        (SELECT COUNT(*) FROM organizations) as orgs_count
      FROM shipments
    `);
    const s = stats.rows[0];

    const system = `Ты — ИИ-помощник платформы ЛОТУС (Национальная цифровая транспортно-логистическая платформа НЦТЛП).

ТЕКУЩИЕ ДАННЫЕ ПЛАТФОРМЫ:
- Всего перевозок: ${s.total_shipments} (активных: ${s.active}, завершённых: ${s.completed})
- Участников (организаций): ${s.orgs_count}
- Цифровых паспортов перевозки (ЦПП): ${s.total_shipments}

ВОЗМОЖНОСТИ ПЛАТФОРМЫ:
- ГИС ЭПД: 19+ млн цифровых транспортных документов в 2025 г.
- Реестры: 1 реестр экспедиторов (будет 16+)
- ЦПП: цифровой двойник каждой перевозки (70+ параметров, 10+ источников данных)
- Единое окно документооборота
- ИИ-аналитика логистических процессов

Отвечай на русском языке. Используй **жирный** для важного.
Специализируйся на: анализе перевозок, таможенных процедурах, документообороте, тарифах, маршрутах.`;

    const client = getClient();
    const response = await client.messages.create({
      model: 'claude-sonnet-4-5-20250929',
      max_tokens: 800,
      system,
      messages: messages.slice(-20),
    });

    const reply = response.content.map(c => c.text || '').join('');
    res.json({ reply, usage: response.usage });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/ai/analyze — анализ конкретной перевозки
router.post('/analyze', async (req, res) => {
  if (!process.env.ANTHROPIC_API_KEY) return res.status(503).json({ error: 'ANTHROPIC_API_KEY не настроен' });
  const { cpp_number, question } = req.body;

  try {
    const { rows } = await db.query(`
      SELECT s.*, o.short_name as shipper_name
      FROM shipments s
      LEFT JOIN organizations o ON o.id = s.shipper_org_id
      WHERE s.cpp_number=$1
    `, [cpp_number]);

    if (!rows[0]) return res.status(404).json({ error: 'Перевозка не найдена' });
    const ship = rows[0];

    const legs = await db.query('SELECT * FROM transport_legs WHERE shipment_id=$1 ORDER BY sequence_number', [ship.id]);
    const cargo = await db.query('SELECT * FROM cargo WHERE shipment_id=$1', [ship.id]);

    const client = getClient();
    const response = await client.messages.create({
      model: 'claude-sonnet-4-5-20250929',
      max_tokens: 600,
      system: 'Ты — аналитик платформы ЛОТУС. Анализируй данные перевозки и давай конкретные рекомендации на русском языке.',
      messages: [{
        role: 'user',
        content: `Данные перевозки ${cpp_number}:
Тип: ${ship.trip_type}
Маршрут: ${ship.origin_address} → ${ship.destination_address}
Статус: ${ship.status}
Модальности: ${(ship.modalities||[]).join(', ')}
Дата начала: ${ship.date_start}
Плечи маршрута: ${legs.rows.map(l => `${l.from_point}→${l.to_point} (${l.mode}, ${l.status})`).join('; ')}
Груз: ${cargo.rows.map(c => `${c.name} ${c.weight_kg}кг`).join('; ')}

Вопрос: ${question || 'Проанализируй текущее состояние перевозки и дай рекомендации.'}`
      }]
    });

    res.json({ analysis: response.content.map(c => c.text || '').join('') });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
