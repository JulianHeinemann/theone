import crypto from 'node:crypto';
import { promisify } from 'node:util';
import jwt from 'jsonwebtoken';

const scrypt = promisify(crypto.scrypt);
const KEYLEN = 64;
const SCRYPT_OPTS = { N: 16384, r: 8, p: 1, maxmem: 64 * 1024 * 1024 };

function secret() {
  const s = process.env.JWT_SECRET;
  if (!s || s.length < 32) throw new Error('JWT_SECRET fehlt oder ist kürzer als 32 Zeichen');
  return s;
}

export async function hashPassword(password) {
  const salt = crypto.randomBytes(16);
  const key = await scrypt(password, salt, KEYLEN, SCRYPT_OPTS);
  return `scrypt$${salt.toString('base64')}$${key.toString('base64')}`;
}

export async function verifyPassword(password, stored) {
  const [algo, saltB64, keyB64] = String(stored).split('$');
  if (algo !== 'scrypt' || !saltB64 || !keyB64) return false;
  const expected = Buffer.from(keyB64, 'base64');
  const key = await scrypt(password, Buffer.from(saltB64, 'base64'), expected.length, SCRYPT_OPTS);
  return key.length === expected.length && crypto.timingSafeEqual(key, expected);
}

export function signToken(user) {
  return jwt.sign({ sub: user.id, email: user.email }, secret(), { expiresIn: '180d', issuer: 'restwert' });
}

export function requireAuth(req, res, next) {
  const header = req.get('authorization') || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Nicht angemeldet.' });
  try {
    const payload = jwt.verify(token, secret(), { issuer: 'restwert' });
    req.userId = payload.sub;
    next();
  } catch {
    res.status(401).json({ error: 'Sitzung abgelaufen. Bitte neu anmelden.' });
  }
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

export function validateCredentials({ email, password }) {
  const e = typeof email === 'string' ? email.trim().toLowerCase() : '';
  const p = typeof password === 'string' ? password : '';
  if (!EMAIL_RE.test(e) || e.length > 254) return { error: 'Bitte gib eine gültige E-Mail-Adresse ein.' };
  if (p.length < 8) return { error: 'Das Passwort braucht mindestens 8 Zeichen.' };
  if (p.length > 200) return { error: 'Das Passwort ist zu lang.' };
  return { email: e, password: p };
}
