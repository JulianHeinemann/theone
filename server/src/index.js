import path from 'node:path';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { migrate, pool } from './db.js';
import { createApp } from './app.js';

const here = path.dirname(fileURLToPath(import.meta.url));
// Web-App liegt im Repo unter restwert/, im Container unter /app/web
const candidates = [process.env.WEB_DIR, path.join(here, '..', 'web'), path.join(here, '..', '..', 'restwert')].filter(Boolean);
const webDir = candidates.find((p) => fs.existsSync(path.join(p, 'index.html')));

await migrate();
const app = createApp({ webDir });
const port = Number(process.env.PORT) || 3000;
const server = app.listen(port, () => console.log(`Restwert API läuft auf :${port}${webDir ? `, Web-App aus ${webDir}` : ''}`));

for (const sig of ['SIGTERM', 'SIGINT']) {
  process.on(sig, () => server.close(() => pool.end().then(() => process.exit(0))));
}
