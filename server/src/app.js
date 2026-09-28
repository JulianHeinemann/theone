import path from 'node:path';
import { fileURLToPath } from 'node:url';
import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import { query } from './db.js';
import { hashPassword, verifyPassword, signToken, requireAuth, validateCredentials } from './auth.js';

const here = path.dirname(fileURLToPath(import.meta.url));


function publicUser(row) {
  return { id: row.id, email: row.email, name: row.name, createdAt: row.created_at };
}

export function createApp() {
  const app = express();
  app.set('trust proxy', 1);
  app.disable('x-powered-by');

  app.use(helmet({
    contentSecurityPolicy: {
      useDefaults: true,
      directives: {
        'script-src': ["'self'", "'unsafe-inline'", "'wasm-unsafe-eval'", 'https://cdn.jsdelivr.net', 'https://cdnjs.cloudflare.com'],
        'style-src': ["'self'", "'unsafe-inline'", 'https://fonts.googleapis.com'],
        'font-src': ["'self'", 'https://fonts.gstatic.com'],
        'img-src': ["'self'", 'data:', 'blob:'],
        'connect-src': ["'self'", 'https://cdn.jsdelivr.net'],
        'worker-src': ["'self'", 'blob:', 'https://cdn.jsdelivr.net'],
      },
    },
  }));
  app.use(cors({ origin: true, credentials: false }));
  // Uploads gibt es nicht mehr: kleine Anfragen reichen (Login, Konto löschen).
  app.use(express.json({ limit: '16kb' }));

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
  // Konten gibt es nicht mehr (die App synchronisiert über iCloud). Neue Konten und neue Kopien nehmen wir nicht an;
  // Altkonten können sich noch anmelden, ihre Daten abrufen und das Konto löschen.
  const GONE = 'Neue Konten und neue Kopien gibt es nicht mehr. Für Abruf oder Löschung eines alten Kontos siehe Datenschutzerklärung.';
  app.post('/api/auth/register', authLimiter, (_req, res) => res.status(410).json({ error: GONE }));

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

  app.put('/api/sync', requireAuth, (_req, res) => res.status(410).json({ error: GONE }));

  // ---- Landingpage, Datenschutz, Impressum ----
  app.use(express.static(path.join(here, '..', 'public'), { extensions: ['html'] }));

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
