// Baut die statische Version (Landingpage + Web-App) für Netlify nach netlify-dist/.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const out = path.join(root, 'netlify-dist');
fs.rmSync(out, { recursive: true, force: true });
fs.cpSync(path.join(root, 'server', 'public'), out, { recursive: true });
fs.mkdirSync(path.join(out, 'app'), { recursive: true });

const body = fs.readFileSync(path.join(root, 'restwert', 'index.html'), 'utf8');
const wrapped = /^\s*<!doctype/i.test(body) ? body : '<!doctype html>\n<html lang="de">\n<head>\n<meta charset="utf-8">\n'
  + '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
  + '<link rel="manifest" href="/manifest.webmanifest">\n<link rel="apple-touch-icon" href="/icon-512.png">\n'
  + '</head>\n<body>\n' + body + '\n</body>\n</html>\n';
fs.writeFileSync(path.join(out, 'app', 'index.html'), wrapped);
for (const page of ['datenschutz', 'impressum']) {
  fs.mkdirSync(path.join(out, page), { recursive: true });
  fs.copyFileSync(path.join(out, `${page}.html`), path.join(out, page, 'index.html'));
}
console.log('netlify-dist gebaut');
