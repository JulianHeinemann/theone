import crypto from 'node:crypto';
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';

process.env.JWT_SECRET ??= 'test-secret-test-secret-test-secret-123';
// Die Tests leeren die Tabelle users: nur gegen eine lokale Test-Datenbank laufen lassen.
const dbUrl = process.env.DATABASE_URL || '';
if (!/@(localhost|127\.0\.0\.1|\[::1\])[:/]/.test(dbUrl) && process.env.ALLOW_DESTRUCTIVE_TESTS !== '1') {
  throw new Error('Tests nur gegen eine lokale Datenbank (DATABASE_URL auf localhost) – sie löschen alle Nutzer.');
}
const { migrate, pool, query } = await import('../src/db.js');
const { createApp } = await import('../src/app.js');

let server;
let base;

before(async () => {
  await migrate();
  await query('DELETE FROM users');
  server = createApp().listen(0);
  base = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  server.close();
  await pool.end();
});

async function call(method, path, body, token) {
  const res = await fetch(base + path, {
    method,
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  return { status: res.status, body: text ? JSON.parse(text) : null };
}

test('health meldet Datenbank', async () => {
  const r = await call('GET', '/health');
  assert.equal(r.status, 200);
  assert.equal(r.body.db, true);
});

test('Keine neuen Konten und keine neuen Kopien; Altkonten können abrufen und löschen', async () => {
  const reg = await call('POST', '/api/auth/register', { email: 'neu@example.de', password: 'geheim123' });
  assert.equal(reg.status, 410);

  // Altkonto direkt anlegen (Registrierung gibt es nicht mehr).
  const { hashPassword } = await import('../src/auth.js');
  await query('INSERT INTO users (id, email, name, password_hash) VALUES ($1, $2, $3, $4)',
    [crypto.randomUUID(), 'test@example.de', 'Test', await hashPassword('geheim123')]);

  const wrong = await call('POST', '/api/auth/login', { email: 'test@example.de', password: 'falsch123' });
  assert.equal(wrong.status, 401);

  const login = await call('POST', '/api/auth/login', { email: 'TEST@example.de', password: 'geheim123' });
  assert.equal(login.status, 200);
  const token = login.body.token;

  const me = await call('GET', '/api/me', null, token);
  assert.equal(me.body.user.name, 'Test');

  const noAuth = await call('GET', '/api/sync');
  assert.equal(noAuth.status, 401);

  const empty = await call('GET', '/api/sync', null, token);
  assert.equal(empty.body.data, null);

  const put = await call('PUT', '/api/sync', { data: { cards: [{ id: 'a' }], tests: [] } }, token);
  assert.equal(put.status, 410);

  const del = await call('DELETE', '/api/me', null, token);
  assert.equal(del.status, 204);
  const after = await call('GET', '/api/me', null, token);
  assert.equal(after.status, 401);
});
