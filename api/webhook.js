import { failure, json, problem, rawBody, verifySignature } from '../lib/security.js';

export default { async fetch(request) {
  try {
    if (request.method !== 'POST') throw problem(405, 'Este receptor recibe eventos por POST.');
    const secret = process.env.TESSERA_WEBHOOK_SECRET;
    if (!secret) throw problem(503, 'El secreto del webhook no está configurado.');
    const body = await rawBody(request);
    if (!verifySignature(request.headers.get('x-tessera-signature'), body, secret)) throw problem(401, 'Firma inválida o caducada.');
    let event; try { event = JSON.parse(body.toString('utf8')); } catch { throw problem(400, 'Evento inválido.'); }
    if (!event || typeof event !== 'object' || Array.isArray(event)) throw problem(400, 'Evento inválido.');
    const type = event.type || event.event;
    if (!['webhook.test', 'certificate.issued', 'certificate.failed', 'certificate.revoked', 'badge.issued', 'credits.low_balance', 'payment.received'].includes(type)) throw problem(400, 'Evento no reconocido.');
    // ponytail: receptor sin efectos ni base propia; los reintentos son seguros.
    // Tessera conserva el estado; la interfaz lo consulta por API. Añadir una
    // cola/base durable solo si se incorporan acciones de negocio propias.
    console.info('Tessera: webhook firmado aceptado', { type });
    return json({ received: true }, 200);
  } catch (error) { return failure(error); }
} };
