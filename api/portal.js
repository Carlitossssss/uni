import { bodyJson, failure, json, problem, requireSession, sameOrigin } from '../lib/security.js';
import { fetchTessera } from '../lib/tessera.js';

const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
export function verificationInput(value) {
  let id = String(value || '').trim();
  if (id.startsWith('https://')) {
    const url = new URL(id);
    if (url.username || url.password || url.port) throw problem(400, 'El enlace no es válido.');
    if (url.hostname === 'tessera.blokis.dev') {
      if (/^\/verify\/\d+\/?$/.test(url.pathname)) id = url.pathname.split('/')[2];
      else if (/^\/verify\/?$/.test(url.pathname)) id = url.searchParams.get('certificateId') || url.searchParams.get('txHash') || url.searchParams.get('tokenId') || '';
      else throw problem(400, 'Pega un enlace de verificación de Tessera válido.');
    } else if (['polygonscan.com','amoy.polygonscan.com','snowtrace.io','testnet.snowtrace.io','43113.routescan.io','43114.routescan.io'].includes(url.hostname) && /^\/tx\/0x[a-f0-9]{64}\/?$/i.test(url.pathname)) id = url.pathname.split('/')[2];
    else throw problem(400, 'Usa un enlace de Tessera o de una transacción de Polygon o Avalanche.');
  }
  if (/^\d{1,78}$/.test(id)) return { tokenId: id };
  if (uuid.test(id)) return { certificateId: id };
  if (/^0x[a-f0-9]{64}$/i.test(id)) return { txHash: id };
  throw problem(400, 'Introduce el número de certificado, su UUID, la transacción o un enlace de Tessera.');
}
export default { async fetch(request) {
  try {
    const url = new URL(request.url); const action = url.searchParams.get('action');
    const isPublic = action === 'verify';
    if (!isPublic) requireSession(request);
    if (action === 'connection' && request.method === 'GET') return json({ apiConfigured: !!process.env.TESSERA_API_KEY, webhookConfigured: !!process.env.TESSERA_WEBHOOK_SECRET });
    if (!['GET', 'POST'].includes(request.method)) throw problem(405, 'Método no permitido.');
    let path, method = 'GET', payload;
    if (request.method === 'GET') {
      const id = url.searchParams.get('id') || '';
      if (action === 'certificates') {
        const page = Math.max(1, Math.min(10000, Number(url.searchParams.get('page')) || 1));
        const query = new URLSearchParams({ page: String(Math.floor(page)), limit: '12' });
        const email = url.searchParams.get('email'); if (email) query.set('studentEmail', email);
        path = '/v1/certificates?' + query;
      } else if (action === 'wallet') path = '/v1/wallet/balance';
      else if (action === 'templates') path = '/v1/templates?limit=100';
      else if (action === 'student') {
        const email = (url.searchParams.get('email') || '').trim();
        if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254) throw problem(400, 'Introduce un email válido.');
        path = '/v1/students/lookup?email=' + encodeURIComponent(email);
      }
      else if (action === 'template' && uuid.test(id)) path = '/v1/templates/' + id;
      else if (action === 'detail' && (uuid.test(id) || /^\d{1,78}$/.test(id))) path = '/v1/certificates/' + id;
      else if (action === 'job' && /^[-a-zA-Z0-9_]{1,200}$/.test(id)) path = '/v1/jobs/' + id;
    } else {
      sameOrigin(request);
      const input = await bodyJson(request);
      if (action === 'verify') { path = '/v1/certificates/verify'; payload = verificationInput(input.identifier); }
      else if (action === 'issue') {
        if (input.confirmed !== true) throw problem(400, 'Confirma la emisión y el consumo de créditos.');
        if (typeof input.idempotencyKey !== 'string' || !uuid.test(input.idempotencyKey)) throw problem(400, 'Falta el identificador seguro de la emisión.');
        path = '/v1/certificates';
        payload = { student: { name: input.student?.name, email: input.student?.email }, achievement: input.achievement, templateId: input.templateId, fieldValues: input.fieldValues, idempotencyKey: input.idempotencyKey };
      } else if (action === 'revoke' && (uuid.test(input.id || '') || /^\d{1,78}$/.test(input.id || ''))) {
        if (input.confirmed !== true) throw problem(400, 'Confirma la revocación.');
        path = '/v1/certificates/' + input.id + '/revoke'; payload = { reason: 'institution_request', reasonText: input.reasonText, publicReason: input.publicReason === true };
      }
      method = 'POST';
    }
    if (!path) throw problem(400, 'La operación o el identificador no son válidos.');
    const base = (process.env.TESSERA_API_BASE || 'https://tessera.blokis.dev/backend').replace(/\/$/, '');
    if (new URL(base).protocol !== 'https:') throw problem(503, 'La conexión con Tessera debe usar HTTPS.');
    if (!isPublic && !process.env.TESSERA_API_KEY) throw problem(503, 'Configura TESSERA_API_KEY en Vercel.');
    const response = await fetchTessera(base + path, { method, headers: { 'Content-Type': 'application/json', ...(!isPublic ? { 'X-API-Key': process.env.TESSERA_API_KEY } : {}) }, body: payload ? JSON.stringify(payload) : undefined, redirect: 'error', signal: AbortSignal.timeout(24000) });
    const text = await response.text();
    let data;
    try { data = JSON.parse(text); } catch {
      if (response.status === 403 && /cloudflare|cf-chl|challenge-platform/i.test(text)) {
        console.error('Tessera: acceso bloqueado por Cloudflare', {status:403,ray:response.headers.get('cf-ray'),challenge:response.headers.get('cf-mitigated')});
        throw problem(502, 'Cloudflare bloqueó la conexión del servidor de Vercel a la API de Tessera (HTTP 403). Revisa el evento de seguridad para /backend/v1/ en Cloudflare. No es un error de tu API key.');
      }
      throw problem(502, `Tessera respondió HTTP ${response.status} sin datos JSON. Revisa TESSERA_API_BASE y el acceso del servidor de Vercel a /backend.`);
    }
    if (!response.ok) return json({ error: data.error?.message || 'Tessera rechazó la solicitud.', details: data.error?.details || null }, response.status);
    return json(data, response.status);
  } catch (error) { return failure(error); }
} };
