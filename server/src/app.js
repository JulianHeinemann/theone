import crypto from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import { query } from './db.js';
import { hashPassword, verifyPassword, signToken, requireAuth, validateCredentials } from './auth.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const MAX_SNAPSHOT_BYTES = 8 * 1024 * 1024;

function publicUser(row) {
  return { id: row.id, email: row.email, name: row.name, createdAt: row.created_at };
}

export function createApp({ webDir } = {}) {
  const app = express();
  app.set('trust proxy', 1);
  app.disable('x-powered-by');

  app.use(helmet({
    contentSecurityPolicy: {
      useDefaults: true,
      directives: {
        'script-src': ["'self'", "'unsafe-inline'", 'https://cdn.jsdelivr.net', 'https://cdnjs.cloudflare.com'],
        'style-src': ["'self'", "'unsafe-inline'", 'https://fonts.googleapis.com'],
        'font-src': ["'self'", 'https://fonts.gstatic.com'],
        'img-src': ["'self'", 'data:', 'blob:'],
        'connect-src': ["'self'", 'https://cdn.jsdelivr.net', 'https://tessdata.projectnaptha.com'],
        'worker-src': ["'self'", 'blob:', 'https://cdn.jsdelivr.net'],
      },
    },
  }));
  app.use(cors({ origin: true, credentials: false }));
  app.use(express.json({ limit: '9mb' }));

  const authLimiter = rateLimit({ windowMs: 15 * 60 * 1000, limit: 30, standardHeaders: 'draft-7', legacyHeaders: false,
    message: { error: 'Zu viele Versuche. Bitte in 15 Minuten erneut probieren.' } });

  app.get('/health', async (_req, res) => {
    try {
      await query('SELECT 1');
      res.json({ ok: true, db: true });
    } catch {
      res.status(503).json({ ok: false, db: false });
    }
  });

  // ---- Auth ----
  app.post('/api/auth/register', authLimiter, async (req, res, next) => {
    try {
      const v = validateCredentials(req.body || {});
      if (v.error) return res.status(400).json({ error: v.error });
      const name = typeof req.body.name === 'string' ? req.body.name.trim().slice(0, 80) : '';
      const exists = await query('SELECT 1 FROM users WHERE email = $1', [v.email]);
      if (exists.rowCount) return res.status(409).json({ error: 'Für diese E-Mail gibt es schon ein Konto. Melde dich an.' });
      const { rows } = await query(
        'INSERT INTO users (id, email, name, password_hash, last_login_at) VALUES ($1, $2, $3, $4, now()) RETURNING *',
        [crypto.randomUUID(), v.email, name, await hashPassword(v.password)],
      );
      res.status(201).json({ token: signToken(rows[0]), user: publicUser(rows[0]) });
    } catch (e) { next(e); }
  });

  app.post('/api/auth/login', authLimiter, async (req, res, next) => {
    try {
      const v = validateCredentials(req.body || {});
      if (v.error) return res.status(400).json({ error: 'E-Mail oder Passwort ist falsch.' });
      const { rows } = await query('SELECT * FROM users WHERE email = $1', [v.email]);
      const user = rows[0];
      const ok = user ? await verifyPassword(v.password, user.password_hash) : await hashPassword(v.password).then(() => false);
      if (!ok) return res.status(401).json({ error: 'E-Mail oder Passwort ist falsch.' });
      await query('UPDATE users SET last_login_at = now() WHERE id = $1', [user.id]);
      res.json({ token: signToken(user), user: publicUser(user) });
    } catch (e) { next(e); }
  });

  app.get('/api/me', requireAuth, async (req, res, next) => {
    try {
      const { rows } = await query('SELECT * FROM users WHERE id = $1', [req.userId]);
      if (!rows[0]) return res.status(401).json({ error: 'Konto nicht gefunden.' });
      res.json({ user: publicUser(rows[0]) });
    } catch (e) { next(e); }
  });

  app.delete('/api/me', requireAuth, async (req, res, next) => {
    try {
      await query('DELETE FROM users WHERE id = $1', [req.userId]);
      res.status(204).end();
    } catch (e) { next(e); }
  });

  // ---- Sync: ein Snapshot pro Nutzer ----
  app.get('/api/sync', requireAuth, async (req, res, next) => {
    try {
      const { rows } = await query('SELECT data, updated_at FROM snapshots WHERE user_id = $1', [req.userId]);
      if (!rows[0]) return res.json({ data: null, updatedAt: null });
      res.json({ data: rows[0].data, updatedAt: rows[0].updated_at.toISOString() });
    } catch (e) { next(e); }
  });

  app.put('/api/sync', requireAuth, async (req, res, next) => {
    try {
      const { data, baseUpdatedAt, device } = req.body || {};
      if (!data || typeof data !== 'object' || !Array.isArray(data.cards)) {
        return res.status(400).json({ error: 'Ungültige Daten.' });
      }
      if (Buffer.byteLength(JSON.stringify(data)) > MAX_SNAPSHOT_BYTES) {
        return res.status(413).json({ error: 'Zu viele Daten. Fotos werden nicht synchronisiert.' });
      }
      const current = await query('SELECT data, updated_at FROM snapshots WHERE user_id = $1', [req.userId]);
      if (current.rows[0] && baseUpdatedAt && new Date(baseUpdatedAt) < current.rows[0].updated_at) {
        return res.status(409).json({
          error: 'Auf einem anderen Gerät wurde inzwischen etwas geändert.',
          data: current.rows[0].data,
          updatedAt: current.rows[0].updated_at.toISOString(),
        });
      }
      const { rows } = await query(
        `INSERT INTO snapshots (user_id, data, updated_at, device) VALUES ($1, $2, now(), $3)
         ON CONFLICT (user_id) DO UPDATE SET data = EXCLUDED.data, updated_at = now(), device = EXCLUDED.device
         RETURNING updated_at`,
        [req.userId, data, typeof device === 'string' ? device.slice(0, 60) : ''],
      );
      res.json({ updatedAt: rows[0].updated_at.toISOString() });
    } catch (e) { next(e); }
  });

  // ---- Web: Landingpage, Datenschutz, Web-App ----
  app.use(express.static(path.join(here, '..', 'public'), { extensions: ['html'] }));
  if (webDir) app.use('/app', express.static(webDir, { extensions: ['html'] }));

  app.use('/api', (_req, res) => res.status(404).json({ error: 'Nicht gefunden.' }));

  // eslint-disable-next-line no-unused-vars
  app.use((err, _req, res, _next) => {
    if (err?.type === 'entity.too.large') return res.status(413).json({ error: 'Zu viele Daten.' });
    if (err?.type === 'entity.parse.failed') return res.status(400).json({ error: 'Ungültiges JSON.' });
    console.error(err);
    res.status(500).json({ error: 'Serverfehler. Bitte später erneut versuchen.' });
  });

  return app;
}
