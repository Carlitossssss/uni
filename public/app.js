'use strict';
const $ = id => document.getElementById(id);
const labels = { issued:'Emitido', confirmed:'Confirmado', revoked:'Revocado', failed:'Falló', queued:'En cola', processing:'En proceso', pending:'Pendiente', retrying:'Reintentando', network_unavailable:'Sin confirmar', not_found:'No encontrado' };
let authenticated=false, page=1, pendingJob=null, timer=null, revokeId=null, templatesReady=false, templateReadyId=null, templateVersion=0, verifyVersion=0;
const completedStates = ['issued','confirmed','completed','revoked','failed'];
const statusLabel = value => labels[value] || 'En proceso';
const date = value => value && !Number.isNaN(Date.parse(value)) ? new Date(value).toLocaleDateString('es',{day:'numeric',month:'short',year:'numeric'}) : 'Pendiente';
function message(id,text,error=false){$(id).textContent=text;$(id).classList.toggle('error',error);}
function safeUrl(value){try{const url=new URL(value);return url.protocol==='https:'&&!url.username&&!url.password?url.href:null;}catch{return null;}}
function link(element,value){const url=safeUrl(value);element.hidden=!url;if(url)element.href=url;else element.removeAttribute('href');}
function node(tag,text,className){const el=document.createElement(tag);if(text!==undefined)el.textContent=text;if(className)el.className=className;return el;}
async function api(action,{method='GET',data,query,signal}={}){
  const url=new URL('/api/portal',location.origin);url.searchParams.set('action',action);for(const [key,value]of Object.entries(query||{}))if(value)url.searchParams.set(key,value);
  const response=await fetch(url,{method,headers:data?{'Content-Type':'application/json'}:undefined,body:data?JSON.stringify(data):undefined,signal:signal||AbortSignal.timeout(28000)});
  const result=await response.json();if(!response.ok){if(response.status===401&&action!=='verify')setAuth(false);throw Error(result.error||'No se pudo completar la solicitud.');}return result;
}
function loading(button,active,text){button.disabled=active;if(active){button.dataset.label=button.textContent;button.textContent=text||'Consultando…';button.setAttribute('aria-busy','true');}else{button.textContent=button.dataset.label||button.textContent;button.removeAttribute('aria-busy');}}
function setAuth(value){authenticated=value;$('staff').hidden=!value;$('login-panel').hidden=value;$('logout').hidden=!value;if(!value){clearTimeout(timer);$('certificates').replaceChildren();$('issue-form').reset();$('custom-fields').replaceChildren();$('completed').value=new Date().toISOString().slice(0,10);$('password').value='';templatesReady=false;$('tracking').hidden=true;}}
function tab(name){for(const key of ['certificates','issue']){const active=key===name;$('tab-'+key).setAttribute('aria-selected',String(active));$('tab-'+key).tabIndex=active?0:-1;$('panel-'+key).hidden=!active;}if(name==='issue'&&!templatesReady)loadTemplates();}
for(const name of ['certificates','issue'])$('tab-'+name).onclick=()=>tab(name);
for(const name of ['certificates','issue'])$('tab-'+name).onkeydown=event=>{if(['ArrowRight','ArrowLeft','Home','End'].includes(event.key)){event.preventDefault();const next=event.key==='Home'?'certificates':event.key==='End'?'issue':name==='issue'?'certificates':'issue';tab(next);$('tab-'+next).focus();}};
$('completed').value=new Date().toISOString().slice(0,10);

async function verify(identifier,{scroll=true}={}){
  const version=++verifyVersion;loading($('verify-button'),true,'Verificando…');$('credential').hidden=true;message('verify-status','Consultando la credencial y su registro en blockchain…');
  try{
    const result=await api('verify',{method:'POST',data:{identifier}});if(version!==verifyVersion)return;
    if(!result.certificate){message('verify-status','No encontramos un certificado emitido con ese identificador. Revisa el número o enlace.',true);return;}
    renderCredential(result);message('verify-status',result.valid?'Certificado verificado.':result.reason==='revoked'?'El certificado está revocado.':'La red no permitió confirmar la validez en este momento.',!result.valid);
    if(scroll)$('credential').scrollIntoView({behavior:'smooth',block:'start'});
  }catch(error){if(version===verifyVersion)message('verify-status',error.name==='TimeoutError'?'La verificación está tardando más de lo habitual. Vuelve a consultar.':error.message,true);}
  finally{if(version===verifyVersion)loading($('verify-button'),false);}
}
$('verify-form').onsubmit=event=>{event.preventDefault();verify($('verify-id').value.trim());};
$('close-credential').onclick=()=>{$('credential').hidden=true;$('verify-id').focus();};
function renderCredential(result){
  const cert=result.certificate;$('credential').hidden=false;$('achievement').textContent=cert.achievement;$('student-name').textContent=cert.studentName;
  $('validity').textContent=result.valid?'Certificado válido':result.reason==='revoked'?'Certificado revocado':'Verificación pendiente';$('validity').className='badge '+(result.valid?'':result.reason==='revoked'?'revoked':'pending');
  $('credential-status').textContent=result.valid?'La credencial está emitida y su registro es verificable.':result.reason==='revoked'?'Esta credencial fue revocada y ya no es válida.':'No se pudo confirmar la validez en la red. Consulta nuevamente antes de darla por válida.';
  $('certificate-data').replaceChildren();for(const [label,value]of [['Institución',cert.institution],['Emitido',date(cert.issuedAt)],['Certificado',cert.tokenId],['Calificación',cert.grade===null||cert.grade===undefined?'No indicada':cert.grade],['Wallet emisora',cert.issuedByWallet]]){const row=node('div');row.append(node('dt',label),node('dd',String(value??'No disponible')));$('certificate-data').append(row);}
  $('networks').replaceChildren();for(const network of result.networks||[]){const row=node('div',undefined,'network');const text=node('div',network.name);text.append(node('small',(network.role==='issuance'?'Emisión principal':'Réplica')+' · '+statusLabel(network.status)));row.append(text);const url=safeUrl(network.txUrl||network.nftUrl||network.contractUrl);if(url){const a=node('a','Ver registro');a.href=url;a.target='_blank';a.rel='noopener';row.append(a);}$('networks').append(row);}
  link($('pdf-link'),result.storage?.downloadUrl);link($('tessera-link'),cert.tokenId?`https://tessera.blokis.dev/verify/${encodeURIComponent(cert.tokenId)}`:null);
  const image=$('certificate-image');image.hidden=true;$('image-status').hidden=false;$('image-status').textContent='Cargando el documento…';
  const imageUrl=safeUrl(result.storage?.imageUrl||result.storage?.imageIpfsUrl);image.onload=()=>{image.hidden=false;$('image-status').hidden=true;};image.onerror=()=>{image.hidden=true;$('image-status').hidden=false;$('image-status').textContent='No se pudo cargar la imagen. Puedes descargar el PDF o abrir el certificado en Tessera.';};if(imageUrl)image.src=imageUrl;else{image.removeAttribute('src');$('image-status').textContent='La credencial no incluye una imagen disponible.';}
}

$('login-form').onsubmit=async event=>{event.preventDefault();loading($('login-button'),true,'Entrando…');message('login-status','');try{const response=await fetch('/api/session',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({password:$('password').value}),signal:AbortSignal.timeout(15000)});const result=await response.json();if(!response.ok)throw Error(result.error);setAuth(true);$('password').value='';await loadStaff();}catch(error){message('login-status',error.message,true);}finally{loading($('login-button'),false);}};
$('logout').onclick=async()=>{try{await fetch('/api/session',{method:'DELETE'});setAuth(false);}catch{message('list-status','No se pudo cerrar la sesión. Inténtalo de nuevo.',true);}};
async function loadStaff(){
  await Promise.allSettled([loadCertificates(),loadBalance(),api('connection').then(c=>{$('integration-status').textContent=c.apiConfigured?(c.webhookConfigured?'Conexión con Tessera configurada · receptor de notificaciones preparado':'Conexión con Tessera configurada · falta configurar las notificaciones'):'Falta configurar la clave de Tessera en Vercel.';})]);
  try{pendingJob=JSON.parse(sessionStorage.getItem('blokis.tracking')||'null');}catch{pendingJob=null;}if(pendingJob){$('tracking').hidden=false;checkJob();}
}
async function loadBalance(){try{const result=await api('wallet');$('balance').textContent=`${result.tsc.balance} TSC disponibles · ${result.tsc.unitsPerCertificate} TSC por certificado`;}catch(error){$('balance').textContent=error.message;}}
let listVersion=0;
async function loadCertificates(){
  const version=++listVersion;message('list-status','Consultando certificados…');$('refresh-certificates').disabled=true;
  try{const result=await api('certificates',{query:{page:String(page),email:$('filter-email').value.trim()}});if(version!==listVersion)return;$('certificates').replaceChildren();
    if(!result.data?.length){const tr=node('tr');const td=node('td','Todavía no hay certificados con estos filtros. Puedes emitir uno desde «Emitir certificado».');td.colSpan=5;tr.append(td);$('certificates').append(tr);}
    for(const cert of result.data||[]){const tr=node('tr');const student=node('td',cert.studentName);student.append(node('small',cert.studentEmail));const status=node('td');status.append(node('span',statusLabel(cert.status),'badge '+(['failed','revoked'].includes(cert.status)?cert.status:['queued','processing'].includes(cert.status)?'pending':'')));const actions=node('td');const group=node('div',undefined,'row-actions');const view=node('button','Ver certificado','button subtle');view.type='button';view.onclick=async()=>{if(cert.tokenId){$('verify-id').value=cert.tokenId;await verify(cert.tokenId);}else message('list-status','El documento estará disponible cuando termine la emisión.');};view.disabled=!cert.tokenId;group.append(view);if(cert.status==='issued'){const revoke=node('button','Revocar','button subtle');revoke.type='button';revoke.onclick=()=>{revokeId=cert.certificateId;$('revoke-form').reset();message('revoke-status','');$('revoke-dialog').showModal();};group.append(revoke);}actions.append(group);tr.append(student,node('td',cert.achievementName),status,node('td',date(cert.issuedAt||cert.createdAt)),actions);$('certificates').append(tr);}
    $('page-label').textContent=`Página ${page} · ${result.pagination?.total||0} certificados`;$('previous').disabled=page<=1;$('next').disabled=!result.pagination?.hasMore;message('list-status','');
  }catch(error){if(version===listVersion)message('list-status',error.message,true);}finally{if(version===listVersion)$('refresh-certificates').disabled=false;}
}
$('filter-form').onsubmit=event=>{event.preventDefault();page=1;loadCertificates();};$('refresh-certificates').onclick=()=>{loadCertificates();loadBalance();};$('previous').onclick=()=>{if(page>1){page--;loadCertificates();}};$('next').onclick=()=>{page++;loadCertificates();};
async function loadTemplates(){
  $('issue-button').disabled=true;templateReadyId=null;templatesReady=false;$('custom-fields').replaceChildren();$('template').disabled=true;message('template-hint','Consultando las plantillas de tu institución…');
  try{const result=await api('templates');$('template').replaceChildren();const placeholder=node('option',result.data?.length?'Selecciona una plantilla':'No hay plantillas disponibles');placeholder.value='';$('template').append(placeholder);for(const item of result.data||[]){const option=node('option',item.name);option.value=item.id;$('template').append(option);}templatesReady=true;message('template-hint',result.data?.length?'':'Crea una plantilla en Tessera y vuelve a abrir este apartado.');if(!result.data?.length)templatesReady=false;}
  catch(error){$('template').replaceChildren(node('option','No se pudieron cargar las plantillas'));message('template-hint',error.message,true);}finally{$('template').disabled=false;}
}
$('retry-templates').onclick=loadTemplates;
$('template').onchange=async()=>{
  const version=++templateVersion;templateReadyId=null;$('custom-fields').replaceChildren();if(!$('template').value){message('template-hint','Selecciona una plantilla.');return;}
  $('issue-button').disabled=true;message('template-hint','Preparando los campos de la plantilla…');
  try{const result=await api('template',{query:{id:$('template').value}});if(version!==templateVersion)return;templateReadyId=$('template').value;
    const fields=result.fields||[];$('grade-field').hidden=!fields.some(f=>f.key==='puntaje');$('description-field').hidden=true;$('custom-fields-title').hidden=!fields.some(f=>!f.automatic);
    for(const field of fields){if(field.automatic)continue;const wrapper=node('div');const input=node('input');input.id='field-'+field.key;input.dataset.key=field.key;input.value=field.defaultValue||'';input.required=field.required!==false;input.maxLength=2000;
      const kind=field.kind||'text';if(['email','date'].includes(kind))input.type=kind;else if(['number','score','year'].includes(kind)){input.type='number';input.min=kind==='year'?'1000':'0';input.step=kind==='year'?'1':'any';if(kind==='score')input.max='100';if(kind==='year')input.max='9999';}else if(kind==='wallet'){input.pattern='0x[a-fA-F0-9]{40}';}
      const label=node('label',field.key.replaceAll('_',' ')+(input.required?'':' (opcional)'));label.htmlFor=input.id;wrapper.append(label,input);$('custom-fields').append(wrapper);}
    message('template-hint','El nombre y los identificadores del certificado se completan automáticamente.');}
  catch(error){if(version===templateVersion)message('template-hint',error.message,true);}finally{if(version===templateVersion)$('issue-button').disabled=templateReadyId!==$('template').value;}
};
$('issue-form').onsubmit=async event=>{
  event.preventDefault();if(templateReadyId!==$('template').value){message('issue-status','Espera a que terminen de cargar los campos de la plantilla.',true);return;}loading($('issue-button'),true,'Enviando certificado…');message('issue-status','Enviando los datos a Tessera…');
  try{
    const student={name:$('student').value.trim(),email:$('email').value.trim()};
    const achievement={name:$('award').value.trim(),completedAt:new Date($('completed').value+'T12:00:00Z').toISOString()};if(!$('description-field').hidden&&$('description').value.trim())achievement.description=$('description').value.trim();if(!$('grade-field').hidden&&$('grade').value!=='')achievement.grade=Number($('grade').value);
    const payload={student,achievement,templateId:$('template').value,fieldValues:Object.fromEntries([...$('custom-fields').querySelectorAll('input')].map(input=>[input.dataset.key,input.value.trim()]))};
    const fingerprint=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(JSON.stringify(payload))))).map(x=>x.toString(16).padStart(2,'0')).join('');
    let previous;try{previous=JSON.parse(sessionStorage.getItem('blokis.issue')||'null');}catch{previous=null;}const key=previous?.fingerprint===fingerprint?previous.key:crypto.randomUUID();sessionStorage.setItem('blokis.issue',JSON.stringify({fingerprint,key}));
    const result=await api('issue',{method:'POST',data:{...payload,idempotencyKey:key,confirmed:$('confirm-issue').checked}});
    pendingJob={jobId:result.jobId||null,certificateId:result.certificateId||null,kind:'issue'};sessionStorage.setItem('blokis.tracking',JSON.stringify(pendingJob));$('tracking').hidden=false;$('new-issue').hidden=false;$('confirm-issue').checked=false;message('issue-status','Solicitud aceptada. El certificado aún debe confirmarse; consulta su progreso debajo.');await checkJob();
  }catch(error){message('issue-status',error.name==='TimeoutError'?'La respuesta está tardando. Reintenta sin cambiar los datos: conservaremos el identificador para evitar una emisión duplicada.':error.message,true);}
  finally{loading($('issue-button'),false);}
};
let checking=false, checks=0;
async function checkJob(){
    if(!pendingJob||!authenticated||checking)return;clearTimeout(timer);checking=true;$('check-job').disabled=true;
  try{
    const result=pendingJob.jobId?await api('job',{query:{id:pendingJob.jobId}}):await api('detail',{query:{id:pendingJob.certificateId}});
    const status=pendingJob.kind==='revoke'?(result.status==='failed'?'failed':result.result?.status==='revoked'||result.status==='revoked'?'revoked':'processing'):(result.result?.status||result.status);const finished=completedStates.includes(status);
    $('tracking-badge').textContent=statusLabel(status);$('tracking-badge').className='badge '+(status==='failed'?'failed':status==='revoked'?'revoked':finished?'':'pending');
    $('tracking-title').textContent=status==='failed'?'No se pudo completar la operación':status==='revoked'?'El certificado fue revocado':finished?'Tu certificado está listo':'Estamos preparando tu certificado';
    $('tracking-description').textContent=status==='failed'?(typeof result.error==='string'?result.error:'Revisa los datos, el saldo y el estado de tu institución en Tessera.'):finished?'El estado quedó registrado en Tessera. Ya puedes actualizar la lista de certificados.':'Tessera está procesando la solicitud. No necesitas volver a emitir; puedes consultar el progreso.';
    $('tracking-id').textContent='Referencia: '+(pendingJob.jobId||pendingJob.certificateId);
    if(finished){checks=0;await Promise.allSettled([loadCertificates(),loadBalance()]);}else if(checks++<15&&!document.hidden)timer=setTimeout(checkJob,8000);
  }catch(error){$('tracking-description').textContent=error.message+' Usa «Consultar estado» para reintentar.';}finally{checking=false;$('check-job').disabled=false;}
}
$('check-job').onclick=()=>{checks=0;checkJob();};
$('new-issue').onclick=()=>{templateReadyId=null;sessionStorage.removeItem('blokis.issue');sessionStorage.removeItem('blokis.tracking');pendingJob=null;clearTimeout(timer);$('tracking').hidden=true;$('new-issue').hidden=true;$('issue-form').reset();$('custom-fields').replaceChildren();$('completed').value=new Date().toISOString().slice(0,10);message('issue-status','Completa los datos de la nueva emisión.');tab('issue');$('student').focus();};
document.addEventListener('visibilitychange',()=>{if(!document.hidden&&pendingJob&&authenticated)checkJob();});
$('cancel-revoke').onclick=()=>$('revoke-dialog').close();
$('revoke-form').onsubmit=async event=>{event.preventDefault();loading($('revoke-button'),true,'Revocando…');message('revoke-status','Enviando la revocación…');try{const result=await api('revoke',{method:'POST',data:{id:revokeId,reasonText:$('revoke-reason').value.trim(),publicReason:$('public-reason').checked,confirmed:$('confirm-revoke').checked}});pendingJob={jobId:result.jobId,certificateId:revokeId,kind:'revoke'};sessionStorage.setItem('blokis.tracking',JSON.stringify(pendingJob));$('tracking').hidden=false;$('revoke-dialog').close();checks=0;await checkJob();}catch(error){message('revoke-status',error.message,true);}finally{loading($('revoke-button'),false);}};
fetch('/api/session').then(async response=>{if(!response.ok)throw Error();const result=await response.json();setAuth(result.signedIn);if(result.signedIn)await loadStaff();}).catch(()=>message('login-status','Publica el proyecto en Vercel para habilitar el acceso institucional.',true));
const initial=new URL(location.href).searchParams.get('certificate');if(initial){$('verify-id').value=initial;verify(initial,{scroll:false});}


let studentVersion=0;
$('email').oninput=()=>{studentVersion++;message('student-status','Puedes consultar si este estudiante pertenece a tu institución.');};
$('find-student').onclick=async()=>{if(!$('email').value||!$('email').reportValidity())return;const version=++studentVersion;loading($('find-student'),true,'Buscando…');message('student-status','Consultando el registro institucional…');try{const result=await api('student',{query:{email:$('email').value.trim()}});if(version!==studentVersion)return;if(result.student){$('student').value=result.student.name||'';message('student-status','Estudiante encontrado. Revisa su nombre antes de emitir.');}else message('student-status','No figura en tu institución. Puedes completar su nombre y emitir por email.');}catch(error){if(version===studentVersion)message('student-status',error.message,true);}finally{loading($('find-student'),false);}};
let scanner;
async function scanTools(){return scanner||=import('./scanner.js');}
$('read-file').onclick=()=>$('certificate-file').click();
$('certificate-file').onchange=async()=>{const file=$('certificate-file').files[0];if(!file)return;loading($('read-file'),true,'Leyendo documento…');message('verify-status','Buscando el QR. El documento se procesa en tu dispositivo.');try{const identifier=await(await scanTools()).readFile(file,text=>message('verify-status',text));$('verify-id').value=identifier;await verify(identifier);if(!$('credential').hidden)message('verify-status','QR leído y credencial consultada. Compara el documento con el original mostrado: leer su QR no demuestra que el archivo no haya sido modificado.');}catch(error){message('verify-status',error.message,true);}finally{$('certificate-file').value='';loading($('read-file'),false);}};
$('scan-camera').onclick=async()=>{loading($('scan-camera'),true,'Abriendo cámara…');try{await(await scanTools()).openCamera(identifier=>{$('verify-id').value=identifier;verify(identifier);});}catch(error){message('verify-status',error.message,true);}finally{loading($('scan-camera'),false);}};
