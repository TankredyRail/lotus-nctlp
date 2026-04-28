const express = require('express');
const router = express.Router();
const db = require('../db/client');
const { optionalAuth } = require('../middleware/auth');

// GET /api/shipments — список перевозок
router.get('/', optionalAuth, async (req, res) => {
  try {
    const { status, limit = 20, offset = 0, user_id } = req.query;

    let where = 'WHERE 1=1';
    const params = [];
    let p = 1;

    if (status && status !== 'all') {
      where += ` AND s.status=$${p++}`;
      params.push(status);
    }
    if (req.user) {
      // Filter by user's organization
      where += ` AND (shipper.inn IS NOT NULL)`; // show all for now
    }

    params.push(Number(limit), Number(offset));

    const { rows } = await db.query(`
      SELECT
        s.id, s.cpp_number, s.trip_type, s.status, s.modalities,
        s.origin_country, s.origin_address, s.destination_country, s.destination_address,
        s.date_start, s.date_end_plan, s.date_end_fact,
        s.coordinator_name, s.params_count, s.data_sources_count, s.documents_count,
        s.created_at,
        shipper.short_name as shipper_name, shipper.inn as shipper_inn,
        receiver.short_name as receiver_name,
        (SELECT COUNT(*) FROM transport_legs tl WHERE tl.shipment_id = s.id) as legs_count,
        (SELECT COUNT(*) FROM cargo c WHERE c.shipment_id = s.id) as cargo_count
      FROM shipments s
      LEFT JOIN organizations shipper ON shipper.id = s.shipper_org_id
      LEFT JOIN organizations receiver ON receiver.id = s.receiver_org_id
      ${where}
      ORDER BY s.created_at DESC
      LIMIT $${p} OFFSET $${p+1}
    `, params);

    const total = await db.query(`SELECT COUNT(*) FROM shipments s ${where}`, params.slice(0,-2));

    res.json({
      shipments: rows,
      total: parseInt(total.rows[0].count),
      limit: Number(limit),
      offset: Number(offset)
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/shipments/:cpp — по номеру ЦПП
router.get('/:cpp', optionalAuth, async (req, res) => {
  try {
    const cpp = decodeURIComponent(req.params.cpp);
    const { rows } = await db.query(`
      SELECT s.*,
        shipper.short_name as shipper_name, shipper.inn as shipper_inn,
        shipper.full_name as shipper_full_name, shipper.legal_address as shipper_address,
        shipper.phone as shipper_phone,
        receiver.short_name as receiver_name, receiver.inn as receiver_inn,
        seller.short_name as seller_name, exporter.short_name as exporter_name
      FROM shipments s
      LEFT JOIN organizations shipper ON shipper.id = s.shipper_org_id
      LEFT JOIN organizations receiver ON receiver.id = s.receiver_org_id
      LEFT JOIN organizations seller ON seller.id = s.seller_org_id
      LEFT JOIN organizations exporter ON exporter.id = s.exporter_org_id
      WHERE s.cpp_number=$1
    `, [cpp]);

    if (!rows[0]) return res.status(404).json({ error: 'Перевозка не найдена' });
    const shipment = rows[0];

    // Transport legs
    const legs = await db.query(`
      SELECT tl.*, o.short_name as carrier_name_short
      FROM transport_legs tl
      LEFT JOIN organizations o ON o.id = tl.carrier_org_id
      WHERE tl.shipment_id=$1
      ORDER BY tl.sequence_number
    `, [shipment.id]);

    // Cargo
    const cargo = await db.query(
      'SELECT * FROM cargo WHERE shipment_id=$1',
      [shipment.id]
    );

    // Documents
    const docs = await db.query(
      'SELECT * FROM documents WHERE shipment_id=$1 ORDER BY created_at DESC',
      [shipment.id]
    );

    // CPP data records
    const cppData = await db.query(
      'SELECT * FROM cpp_data_records WHERE shipment_id=$1 ORDER BY category, param_name',
      [shipment.id]
    );

    res.json({
      ...shipment,
      legs: legs.rows,
      cargo: cargo.rows,
      documents: docs.rows,
      cpp_data: cppData.rows,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// POST /api/shipments — создать перевозку
router.post('/', optionalAuth, async (req, res) => {
  const {
    trip_type, modalities = [], status = 'active',
    origin_country = 'Российская Федерация', origin_address,
    destination_country, destination_address,
    date_start, date_end_plan,
    coordinator_name, shipper_inn, cargo_name,
    packaging_type, weight_kg, volume_m3,
    contact_name, contact_phone
  } = req.body;

  if (!trip_type || !origin_address || !destination_address || !date_start) {
    return res.status(400).json({ error: 'Обязательные поля: trip_type, origin_address, destination_address, date_start' });
  }

  try {
    // Generate CPP number
    const year = new Date().getFullYear();
    const seqRes = await db.query("SELECT nextval('cpp_sequence') as seq");
    const seq = String(seqRes.rows[0].seq).padStart(3, '0');
    const rand = Math.floor(1000 + Math.random() * 9000);
    const cpp_number = `ЦПП-${rand}-${year}-${seq}`;

    // Find shipper org
    let shipper_id = null;
    if (shipper_inn) {
      const org = await db.query('SELECT id FROM organizations WHERE inn=$1', [shipper_inn]);
      shipper_id = org.rows[0]?.id;
    } else if (req.user?.org_id) {
      shipper_id = req.user.org_id;
    }

    const { rows } = await db.query(`
      INSERT INTO shipments (
        cpp_number, trip_type, status, modalities,
        origin_country, origin_address, destination_country, destination_address,
        date_start, date_end_plan, coordinator_name, shipper_org_id,
        created_by
      ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
      RETURNING *
    `, [
      cpp_number, trip_type, status, modalities,
      origin_country, origin_address,
      destination_country || 'Российская Федерация', destination_address,
      date_start, date_end_plan || null, coordinator_name || null,
      shipper_id, req.user?.id || null
    ]);

    const shipment = rows[0];

    // Add cargo if provided
    if (cargo_name) {
      await db.query(`
        INSERT INTO cargo (shipment_id, name, packaging_type, weight_kg, volume_m3)
        VALUES ($1,$2,$3,$4,$5)
      `, [shipment.id, cargo_name, packaging_type, weight_kg || null, volume_m3 || null]);
    }

    res.status(201).json(shipment);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// PATCH /api/shipments/:cpp — обновить статус
router.patch('/:cpp', optionalAuth, async (req, res) => {
  try {
    const cpp = decodeURIComponent(req.params.cpp);
    const allowed = ['status', 'date_end_fact', 'coordinator_name'];
    const updates = {};
    for (const k of allowed) if (req.body[k] !== undefined) updates[k] = req.body[k];
    updates.updated_at = new Date().toISOString();

    const sets = Object.keys(updates).map((k, i) => `${k}=$${i+2}`).join(',');
    const vals = Object.values(updates);

    const { rows } = await db.query(
      `UPDATE shipments SET ${sets} WHERE cpp_number=$1 RETURNING *`,
      [cpp, ...vals]
    );
    if (!rows[0]) return res.status(404).json({ error: 'Не найдено' });
    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/shipments/stats/summary
router.get('/stats/summary', async (req, res) => {
  try {
    const { rows } = await db.query(`
      SELECT
        COUNT(*) as total,
        COUNT(*) FILTER (WHERE status='active') as active,
        COUNT(*) FILTER (WHERE status='completed') as completed,
        COUNT(*) FILTER (WHERE 'auto'=ANY(modalities)) as with_auto,
        COUNT(*) FILTER (WHERE 'rail'=ANY(modalities)) as with_rail,
        COUNT(*) FILTER (WHERE 'sea'=ANY(modalities)) as with_sea
      FROM shipments
    `);
    res.json(rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
