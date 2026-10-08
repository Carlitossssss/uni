let qrLibrary, pdfLibrary;
const byId = id => document.getElementById(id);
function loadQR() {
  return qrLibrary ||= new Promise((resolve, reject) => {
    const script = document.createElement('script'); script.src = '/vendor/jsQR.js';
    script.onload = () => resolve(window.jsQR);
    script.onerror = () => { qrLibrary = null; script.remove(); reject(Error('No se pudo cargar el lector QR. Inténtalo de nuevo.')); };
    document.head.append(script);
  });
}
async function decode(canvas) {
  const qr = await loadQR(); const ctx = canvas.getContext('2d', { willReadFrequently: true });
  const data = ctx.getImageData(0, 0, canvas.width, canvas.height);
  const result = qr(data.data, data.width, data.height, { inversionAttempts: 'attemptBoth' });
  if (result) return result.data;
  // Dense certificate QRs are easier to locate without the surrounding artwork.
  const side = Math.ceil(Math.min(canvas.width, canvas.height) * .45);
  for (const [x,y] of [[0,0],[canvas.width-side,0],[0,canvas.height-side],[canvas.width-side,canvas.height-side]]) {
    const crop = ctx.getImageData(x,y,side,side);
    const code = qr(crop.data,side,side,{inversionAttempts:'attemptBoth'}); if(code)return code.data;
  }
  return null;
}
async function imageCanvas(source) {
  const canvas = document.createElement('canvas');
  const width = source.width || source.videoWidth, height = source.height || source.videoHeight;
  const scale = Math.min(1, 1800 / Math.max(width, height));
  canvas.width = Math.round(width * scale); canvas.height = Math.round(height * scale);
  canvas.getContext('2d').drawImage(source, 0, 0, canvas.width, canvas.height); return canvas;
}
export async function readFile(file, progress = () => {}) {
  if (file.size > 12 * 1024 * 1024) throw Error('El archivo supera 12 MB. Usa una imagen del QR o un PDF más pequeño.');
  if (!file.size) throw Error('El archivo está vacío.');
  if (file.type === 'application/pdf' || /\.pdf$/i.test(file.name)) {
    const pdfjs = await (pdfLibrary ||= import('/vendor/pdf.mjs').catch(error => { pdfLibrary = null; throw error; }));
    pdfjs.GlobalWorkerOptions.workerSrc = '/vendor/pdf.worker.mjs';
    const task = pdfjs.getDocument({ data: new Uint8Array(await file.arrayBuffer()), isEvalSupported: false });
    try {
      const pdf = await task.promise;
      // ponytail: bounded scanning; use a cropped QR image for PDFs beyond ten pages.
      for (let index = 1; index <= Math.min(pdf.numPages, 10); index++) {
        progress(`Buscando el QR en la página ${index} de ${pdf.numPages}…`);
        const page = await pdf.getPage(index), initial = page.getViewport({ scale: 1 });
        const viewport = page.getViewport({ scale: Math.min(4, 2800 / Math.max(initial.width, initial.height)) });
        const canvas = document.createElement('canvas'); canvas.width = Math.ceil(viewport.width); canvas.height = Math.ceil(viewport.height);
        await page.render({ canvasContext: canvas.getContext('2d'), viewport }).promise;
        const result = await decode(canvas); page.cleanup(); if (result) return result;
      }
      throw Error('No encontramos un QR legible en las primeras diez páginas. Sube una imagen del QR o pega el enlace.');
    } catch (error) {
      if (error.name === 'PasswordException') throw Error('El PDF tiene contraseña. Usa una imagen del QR o una copia desbloqueada.');
      if (error.name === 'InvalidPDFException') throw Error('El archivo no es un PDF válido.');
      throw error;
    } finally { await task.destroy(); }
  }
  if (!['image/png', 'image/jpeg', 'image/webp'].includes(file.type)) throw Error('Selecciona un PDF o una imagen PNG, JPG o WebP.');
  let bitmap;
  try { bitmap = await createImageBitmap(file); const result = await decode(await imageCanvas(bitmap)); if (!result) throw Error('No encontramos un QR legible. Sube una imagen más nítida o pega el enlace.'); return result; }
  finally { bitmap?.close(); }
}
let stream, cameraVersion = 0, cameraTimer;
function closeCamera() {
  cameraVersion++; clearTimeout(cameraTimer); stream?.getTracks().forEach(track => track.stop()); stream = null;
  byId('camera-video').srcObject = null;
  if (byId('camera-dialog').open) byId('camera-dialog').close();
}
byId('close-camera').onclick = closeCamera;
byId('camera-dialog').addEventListener('close', closeCamera);
document.addEventListener('visibilitychange', () => { if (document.hidden) closeCamera(); });
export async function openCamera(onRead) {
  if (!navigator.mediaDevices?.getUserMedia) throw Error('La cámara necesita HTTPS y un navegador compatible. Puedes subir el documento.');
  closeCamera(); const version = cameraVersion;
  byId('camera-status').textContent = 'Esperando permiso de cámara…'; byId('camera-dialog').showModal();
  try {
    const camera = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: 'environment' }, width: { ideal: 1280 } }, audio: false });
    if (version !== cameraVersion) { camera.getTracks().forEach(track => track.stop()); return; }
    stream = camera; const video = byId('camera-video'); video.srcObject = stream; await video.play();
    const started = Date.now();
    byId('camera-status').textContent = 'Acerca el QR hasta que se vea nítido. No se guardan imágenes.';
    const frame = async () => {
      if (version !== cameraVersion) return;
      try {
        const result = video.readyState >= 2 ? await decode(await imageCanvas(video)) : null;
        if (version !== cameraVersion) return;
        if (result) { closeCamera(); onRead(result); return; }
        if (Date.now() - started > 90000) { closeCamera(); throw Error('No se leyó el QR en 90 segundos. Puedes subir una imagen o volver a abrir la cámara.'); }
        cameraTimer = setTimeout(frame, 350);
      } catch (error) { closeCamera(); byId('verify-status').textContent = error.message; byId('verify-status').classList.add('error'); }
    };
    await frame();
  } catch (error) { closeCamera(); throw Error(error.name === 'NotAllowedError' ? 'No diste permiso para usar la cámara. Puedes subir el PDF o una imagen.' : error.name === 'NotFoundError' ? 'No encontramos una cámara. Puedes subir el documento.' : error.message); }
}
