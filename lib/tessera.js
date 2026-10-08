import https from 'node:https';
import { isIP } from 'node:net';
import { problem } from './security.js';

const originAgent = new https.Agent({ keepAlive: true, timeout: 24000 });

export async function fetchTessera(address, options) {
  const ip = process.env.TESSERA_ORIGIN_IP?.trim();
  if (!ip) return fetch(address, options);
  const url = new URL(address);
  if (!isIP(ip) || url.protocol !== 'https:' || url.hostname !== 'tessera.blokis.dev' || (url.port && url.port !== '443') || url.username || url.password || !url.pathname.startsWith('/backend/v1/')) {
    throw problem(503, 'La conexión directa requiere una IP válida y la API HTTPS oficial de Tessera.');
  }
  // Only DNS resolution changes. Host, SNI and certificate validation retain the official domain.
  return new Promise((resolve, reject) => {
    const request = https.request(url, {
      method: options.method, headers: options.headers, signal: options.signal,
      agent: originAgent, servername: url.hostname, rejectUnauthorized: true,
      lookup: (_host, settings, callback) => settings.all
        ? callback(null, [{ address: ip, family: isIP(ip) }])
        : callback(null, ip, isIP(ip)),
    }, response => {
      if (response.statusCode >= 300 && response.statusCode < 400) {
        response.resume(); reject(problem(502, 'La API redirigió la solicitud. No se reenvían claves a otros destinos.')); return;
      }
      const chunks = []; let size = 0;
      response.on('data', chunk => {
        size += chunk.length;
        if (size > 4 * 1024 * 1024) { response.destroy(problem(502, 'La respuesta de Tessera supera el tamaño permitido.')); return; }
        chunks.push(chunk);
      });
      response.on('error', reject);
      response.on('end', () => resolve(new Response(Buffer.concat(chunks), {
        status: response.statusCode,
        headers: { 'Content-Type': response.headers['content-type'] || 'application/json' },
      })));
    });
    request.on('error', reject); request.end(options.body);
  });
}
