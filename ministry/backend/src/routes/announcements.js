const express = require('express');
const router = express.Router();
const db = require('../db');

const MAX_TITLE = 200;
const MAX_BODY = 4000;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const VALID_AUDIENCE = new Set(['both', 'mobile', 'pos']);

function sanitize(value, max) {
  if (value == null) return '';
  return String(value).trim().slice(0, max);
}

function sanitizeAudience(value) {
  const v = String(value || 'both').trim().toLowerCase();
  return VALID_AUDIENCE.has(v) ? v : 'both';
}

router.post('/', async (req, res) => {
  const title = sanitize(req.body?.title, MAX_TITLE);
  const body = sanitize(req.body?.body, MAX_BODY);
  const audience = sanitizeAudience(req.body?.audience);

  if (!title) return res.status(400).json({ error: 'title is required' });
  if (!body) return res.status(400).json({ error: 'body is required' });

  try {
    const result = await db.query(
      `INSERT INTO health_news (title, body, audience)
       VALUES ($1, $2, $3)
       RETURNING news_id AS id, title, body, audience, is_active, published_at AS created_at, published_at AS updated_at`,
      [title, body, audience]
    );
    res.status(201).json({ status: 'success', data: result.rows[0] });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.get('/', async (req, res) => {
  const includeInactive = String(req.query.include_inactive || '') === 'true';
  try {
    const result = await db.query(
      `SELECT news_id AS id, title, body, audience, is_active, published_at AS created_at, published_at AS updated_at
       FROM health_news
       ${includeInactive ? '' : 'WHERE is_active = true'}
       ORDER BY published_at DESC
       LIMIT 200`
    );
    res.json({ status: 'success', data: result.rows });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

router.patch('/:id/deactivate', async (req, res) => {
  const id = String(req.params.id || '').trim();
  if (!UUID_RE.test(id)) {
    return res.status(400).json({ error: 'invalid id' });
  }
  try {
    const result = await db.query(
      `UPDATE health_news
       SET is_active = false
       WHERE news_id = $1::uuid
       RETURNING news_id AS id, title, body, audience, is_active, published_at AS created_at, published_at AS updated_at`,
      [id]
    );
    if (!result.rows.length) return res.status(404).json({ error: 'not found' });
    res.json({ status: 'success', data: result.rows[0] });
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

module.exports = router;
