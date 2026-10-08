import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { bodyJson, createSession, signedIn, verifySignature } from '../lib/security.js';
import portal, { verificationInput } from '../api/portal.js';
import session from '../api/session.js';
import webhook from '../api/webhook.js';

const origin='https://academia.example';
const request=(path,options={})=>new Request(origin+path,options);
const post=(path,data,headers={})=>request(path,{method:'POST',headers:{origin,'Content-Type':'application/json',...headers},body:JSON.stringify(data)});
process.env.ADMIN_PASSWORD='test-password-not-a-real-secret';
process.env.TESSERA_API_KEY='test-key-not-a-real-secret';
process.env.TESSERA_WEBHOOK_SECRET='test-webhook-not-a-real-secret';
const cookie=()=>`blokis_session=${createSession()}`;

test('sesión firmada: caducidad, manipulación y cookie HttpOnly',async()=>{
  const token=createSession(1000);const req=request('/api/session',{headers:{cookie:'blokis_session='+token}});
  assert(signedIn(req,1000));assert(!signedIn(req,1000+8*60*60*1000+1));
  assert(!signedIn(request('/api/session',{headers:{cookie:'blokis_session='+token+'x'} }),1000));
  const result=await session.fetch(post('/api/session',{password:process.env.ADMIN_PASSWORD}));assert.equal(result.status,200);assert.match(result.headers.get('set-cookie'),/HttpOnly; SameSite=Strict/);assert.match(result.headers.get('set-cookie'),/Secure/);
  assert.equal((await session.fetch(post('/api/session',{password:'wrong'}))).status,401);
  assert.equal((await session.fetch(post('/api/session',{password:process.env.ADMIN_PASSWORD},{origin:'https://another-institution.example'}))).status,403);
});
test('verificación acepta token, UUID, transacción o enlace oficial; rechaza otros enlaces',()=>{
  assert.deepEqual(verificationInput('https://tessera.blokis.dev/verify/37'),{tokenId:'37'});
  assert.deepEqual(verificationInput('37'),{tokenId:'37'});
  assert.deepEqual(verificationInput('11111111-1111-4111-8111-111111111111'),{certificateId:'11111111-1111-4111-8111-111111111111'});
  assert.throws(()=>verificationInput('https://attacker.example/verify/37'));assert.throws(()=>verificationInput('abc'));
});
test('datos privados y escrituras exigen sesión, origen y confirmación',async()=>{
  assert.equal((await portal.fetch(request('/api/portal?action=certificates'))).status,401);
  const auth={cookie:cookie()};assert.equal((await portal.fetch(post('/api/portal?action=issue',{},auth))).status,400);
  assert.equal((await portal.fetch(post('/api/portal?action=issue',{confirmed:true,idempotencyKey:'not-a-uuid'},auth))).status,400);
  assert.equal((await portal.fetch(post('/api/portal?action=issue',{}, {...auth,origin:'https://other.example'}))).status,403);
  assert.equal((await portal.fetch(request('/api/portal?action=https://attacker.example',{headers:auth}))).status,400);
});
test('proxy permite únicamente rutas conocidas y no envía la clave en verificación pública',async()=>{
  const original=globalThis.fetch;const calls=[];globalThis.fetch=async(url,options)=>{calls.push({url,options});return new Response('{"valid":true}',{headers:{'Content-Type':'application/json'}});};
  try{
    assert.equal((await portal.fetch(post('/api/portal?action=verify',{identifier:'37'}))).status,200);
    assert.equal(calls[0].options.headers['X-API-Key'],undefined);
    assert.match(calls[0].url,/\/v1\/certificates\/verify$/);
    await portal.fetch(request('/api/portal?action=templates',{headers:{cookie:cookie()}}));
    assert.match(calls[1].url,/\/v1\/templates\?limit=100$/);assert.equal(calls[1].options.headers['X-API-Key'],process.env.TESSERA_API_KEY);
    const data=await(await portal.fetch(request('/api/portal?action=connection',{headers:{cookie:cookie()}}))).text();assert(!data.includes(process.env.TESSERA_API_KEY));
  }finally{globalThis.fetch=original;}
});
test('webhook valida cuerpo original, antigüedad y secreto institucional; admite formato real y prueba',async()=>{
  for(const event of [{id:'evt_test',type:'webhook.test'},{event:'certificate.issued',jobId:'job_test'}]){
    const raw=JSON.stringify(event), t=Math.floor(Date.now()/1000);const header=`t=${t},v1=${createHmac('sha256',process.env.TESSERA_WEBHOOK_SECRET).update(t+'.'+raw).digest('hex')}`;
    assert(verifySignature(header,Buffer.from(raw),process.env.TESSERA_WEBHOOK_SECRET));assert(!verifySignature(header,Buffer.from(raw+' '),process.env.TESSERA_WEBHOOK_SECRET));assert(!verifySignature(header,Buffer.from(raw),'other-institution'));assert(!verifySignature(header,Buffer.from(raw),process.env.TESSERA_WEBHOOK_SECRET,Date.now()+301000));
    const delivered=()=>webhook.fetch(request('/api/webhook',{method:'POST',headers:{'x-tessera-signature':header},body:raw}));assert.equal((await delivered()).status,200);assert.equal((await delivered()).status,200);
  }
  assert.equal((await webhook.fetch(post('/api/webhook',{event:'certificate.issued'}))).status,401);
});
test('cuerpos sobredimensionados se rechazan antes de reenviar',async()=>{
  await assert.rejects(bodyJson(post('/api/portal',{large:'x'.repeat(66000)})),error=>error.status===413);
});
