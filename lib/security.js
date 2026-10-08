import { createHmac, timingSafeEqual, randomBytes } from 'node:crypto';

export const problem = (status, message) => Object.assign(new Error(message), { status });
export const json = (data, status = 200, headers = {}) => new Response(JSON.stringify(data), {
  status, headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', ...headers },
});
export function equal(a, b) {
  const x = Buffer.from(a), y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
}
export function sameOrigin(request) {
  if (request.headers.get('origin') !== new URL(request.url).origin) throw problem(403, 'La solicitud debe realizarse desde este portal.');
}
function sign(value) { return createHmac('sha256', 'blokis-session:' + (process.env.ADMIN_PASSWORD || '')).update(value).digest('base64url'); }
export function createSession(now = Date.now()) {
  const payload = Buffer.from(JSON.stringify({ expires: now + 8 * 60 * 60 * 1000, nonce: randomBytes(16).toString('hex') })).toString('base64url');
  return payload + '.' + sign(payload);
}
export function signedIn(request, now = Date.now()) {
  if ((process.env.ADMIN_PASSWORD || '').length < 16) return false;
  const token = request.headers.get('cookie')?.split(';').map(s => s.trim()).find(s => s.startsWith('blokis_session='))?.slice(15);
  if (!token) return false;
  const [payload, signature, extra] = token.split('.');
  if (!payload || !signature || extra || !equal(sign(payload), signature)) return false;
  try { const data = JSON.parse(Buffer.from(payload, 'base64url').toString()); return Number.isFinite(data.expires) && data.expires > now && data.expires <= now + 8 * 60 * 60 * 1000; }
  catch { return false; }
}
export function requireSession(request) { if (!signedIn(request)) throw problem(401, 'Inicia sesión para acceder a los certificados de la institución.'); }
export async function bodyJson(request) {
  if (!request.headers.get('content-type')?.startsWith('application/json')) throw problem(415, 'Envía datos JSON.');
  const raw = await rawBody(request, 65536);
  try { const data = JSON.parse(raw.toString('utf8')); if (!data || Array.isArray(data) || typeof data !== 'object') throw Error(); return data; }
  catch { throw problem(400, 'Los datos de la solicitud no son válidos.'); }
}
export async function rawBody(request, limit = 262144) {
  const reader = request.body?.getReader(); if (!reader) throw problem(400, 'Falta el evento.');
  const chunks = []; let size = 0;
  try { while (true) { const { value, done } = await reader.read(); if (done) break; size += value.length; if (size > limit) { await reader.cancel(); throw problem(413, 'La solicitud es demasiado grande.'); } chunks.push(value); } }
  finally { reader.releaseLock(); }
  return Buffer.concat(chunks);
}
export function verifySignature(header, raw, secret, now = Date.now()) {
  const parts = typeof header === 'string' && /^t=(\d+),v1=([a-f0-9]{64})$/.exec(header);
  if (!secret || !parts || Math.abs(Math.floor(now / 1000) - Number(parts[1])) > 300) return false;
  return equal(createHmac('sha256', secret).update(parts[1] + '.').update(raw).digest('hex'), parts[2]);
}
export function failure(error) {
  return json({ error: error.status ? error.message : 'No se pudo contactar con Tessera. Inténtalo de nuevo; conserva el identificador de la emisión si ya la enviaste.' }, error.status || 502);
}
