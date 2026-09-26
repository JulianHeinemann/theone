import { migrate, pool } from './db.js';
import { createApp } from './app.js';

await migrate();
const app = createApp();
const port = Number(process.env.PORT) || 3000;
const server = app.listen(port, () => console.log(`Restwert API läuft auf :${port}`));

for (const sig of ['SIGTERM', 'SIGINT']) {
  process.on(sig, () => server.close(() => pool.end().then(() => process.exit(0))));
}
