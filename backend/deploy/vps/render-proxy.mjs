// Reenvío de Render a la VPS (tanda 2 del corte, ver backend/README.md → "VPS").
// API_BASE_URL de la app es fija al compilar: las versiones ya instaladas siguen
// llamando a oneofone-backend.onrender.com. Este proceso las pasa tal cual a
// api.buschfranco.com (método, ruta, headers y cuerpo), sin tocar la base.
// Sin dependencias: lo arranca Render con `node deploy/vps/render-proxy.mjs`.
import http from 'node:http';
import { Readable } from 'node:stream';

const UPSTREAM = (process.env.UPSTREAM_URL ?? 'https://api.buschfranco.com').replace(/\/$/, '');
const PORT = Number(process.env.PORT ?? 3000);

// Headers que no se reenvían (son de cada conexión, no del pedido).
const HOP = new Set([
  'connection', 'keep-alive', 'transfer-encoding', 'upgrade', 'host',
  'proxy-connection', 'te', 'trailer', 'content-length',
]);

http
  .createServer(async (req, res) => {
    // Health check de Render: responde este proceso, sin depender de la VPS.
    if (req.url === '/health' && req.method === 'GET') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end('{"ok":true,"proxy":true}');
      return;
    }
    const headers = {};
    for (const [k, v] of Object.entries(req.headers)) {
      if (!HOP.has(k) && v !== undefined) headers[k] = Array.isArray(v) ? v.join(', ') : v;
    }
    const hasBody = req.method !== 'GET' && req.method !== 'HEAD';
    try {
      const up = await fetch(UPSTREAM + req.url, {
        method: req.method,
        headers,
        body: hasBody ? Readable.toWeb(req) : undefined,
        duplex: hasBody ? 'half' : undefined,
        redirect: 'manual',
        signal: AbortSignal.timeout(60_000),
      });
      const out = {};
      up.headers.forEach((v, k) => {
        // fetch ya descomprime el cuerpo: no se reenvía la codificación original.
        if (!HOP.has(k) && k !== 'content-encoding') out[k] = v;
      });
      res.writeHead(up.status, out);
      if (up.body) Readable.fromWeb(up.body).pipe(res);
      else res.end();
    } catch (e) {
      console.error(`proxy ${req.method} ${req.url} falló: ${e?.message ?? e}`);
      if (!res.headersSent) res.writeHead(502, { 'content-type': 'application/json' });
      res.end('{"message":"Servidor no disponible"}');
    }
  })
  .listen(PORT, '0.0.0.0', () => console.log(`proxy 1of1 en :${PORT} -> ${UPSTREAM}`));
