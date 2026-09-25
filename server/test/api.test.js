import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';

process.env.JWT_SECRET ??= 'test-secret-test-secret-test-secret-123';
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

test('Registrierung, Login, Sync, Konflikt, Löschen', async () => {
  const bad = await call('POST', '/api/auth/register', { email: 'kaputt', password: '123' });
  assert.equal(bad.status, 400);

  const reg = await call('POST', '/api/auth/register', { email: 'Test@Example.de', password: 'geheim123', name: 'Test' });
  assert.equal(reg.status, 201);
  assert.equal(reg.body.user.email, 'test@example.de');
  const token = reg.body.token;

  const dup = await call('POST', '/api/auth/register', { email: 'test@example.de', password: 'geheim123' });
  assert.equal(dup.status, 409);

  const wrong = await call('POST', '/api/auth/login', { email: 'test@example.de', password: 'falsch123' });
  assert.equal(wrong.status, 401);

  const login = await call('POST', '/api/auth/login', { email: 'TEST@example.de', password: 'geheim123' });
  assert.equal(login.status, 200);

  const me = await call('GET', '/api/me', null, login.body.token);
  assert.equal(me.body.user.name, 'Test');

  const noAuth = await call('GET', '/api/sync');
  assert.equal(noAuth.status, 401);

  const empty = await call('GET', '/api/sync', null, token);
  assert.equal(empty.body.data, null);

  const put1 = await call('PUT', '/api/sync', { data: { cards: [{ id: 'a' }], tests: [] }, device: 'iPhone' }, token);
  assert.equal(put1.status, 200);
  const t1 = put1.body.updatedAt;

  const put2 = await call('PUT', '/api/sync', { data: { cards: [{ id: 'a' }, { id: 'b' }], tests: [] }, baseUpdatedAt: t1 }, token);
  assert.equal(put2.status, 200);

  const conflict = await call('PUT', '/api/sync', { data: { cards: [], tests: [] }, baseUpdatedAt: t1 }, token);
  assert.equal(conflict.status, 409);
  assert.equal(conflict.body.data.cards.length, 2);

  const got = await call('GET', '/api/sync', null, token);
  assert.equal(got.body.data.cards.length, 2);

  const invalid = await call('PUT', '/api/sync', { data: { nope: true } }, token);
  assert.equal(invalid.status, 400);

  const del = await call('DELETE', '/api/me', null, token);
  assert.equal(del.status, 204);
  const after = await call('GET', '/api/me', null, token);
  assert.equal(after.status, 401);
});
