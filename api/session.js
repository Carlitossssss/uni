import { bodyJson, createSession, equal, failure, json, problem, sameOrigin, signedIn } from '../lib/security.js';

export default { async fetch(request) {
  try {
    if (request.method === 'GET') return json({ signedIn: signedIn(request) });
    sameOrigin(request);
    const secure = new URL(request.url).protocol === 'https:' ? '; Secure' : '';
    if (request.method === 'DELETE') return json({ signedIn: false }, 200, { 'Set-Cookie': 'blokis_session=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0' + secure });
    if (request.method !== 'POST') throw problem(405, 'Método no permitido.');
    const password = process.env.ADMIN_PASSWORD || '';
    if (password.length < 16) throw problem(503, 'Configura ADMIN_PASSWORD con al menos 16 caracteres en Vercel.');
    const input = await bodyJson(request);
    if (typeof input.password !== 'string' || !equal(input.password, password)) throw problem(401, 'La contraseña institucional no es correcta.');
    return json({ signedIn: true }, 200, { 'Set-Cookie': `blokis_session=${createSession()}; Path=/; HttpOnly; SameSite=Strict; Max-Age=28800${secure}` });
  } catch (error) { return failure(error); }
} };
