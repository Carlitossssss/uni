# Blokis Academia

Portal académico demostrativo conectado a la API real de Tessera. HTML, CSS y
JavaScript, sin framework ni dependencias. Las funciones de Vercel protegen la
clave institucional, la sesión y las firmas del webhook. No tiene base propia:
certificados, plantillas, trabajos y saldo se consultan en Tessera.

Incluye verificación pública con imagen, PDF, emisor, estado de Polygon y
Avalanche y enlace a Tessera. El área institucional permite listar y filtrar
certificados, emitir con una plantilla existente, seguir la emisión y revocar.
No añade cursos, alumnos ficticios ni endpoints inexistentes de insignias.

## Desplegar en Vercel

El repositorio conectado es `Carlitossssss/uni`. Si importas ese repositorio:

El portal está publicado en la rama **`codex/blokis-academia`**; `master`
todavía contiene el proyecto anterior. Despliega esa rama. Si el proyecto ya
está creado, abre Settings → Environments → Production → Branch Tracking y establece
`codex/blokis-academia` como rama de producción. En interfaces anteriores
esa opción aparece en Settings → Git. Después crea un despliegue Production
de esa rama desde Deployments. No despliegues `master` esperando ver el portal.

- Project Name: `blokis-academia` o el nombre que tengas disponible.
- Root Directory: `./` (la raíz de **este repositorio uni**, no del workspace).
- Application Preset: **Other**.
- Build Command: vacío / override desactivado.
- Install Command: predeterminado; no hay dependencias.
- Output Directory: `public` (también fijado en `vercel.json`).
- Node.js: `24.x`, indicado en `package.json`.

Variables de entorno del servidor en Production:

| Variable | Valor |
|---|---|
| `TESSERA_API_KEY` | Clave privada de la institución con `certificates:read`, `certificates:write`, `wallet:read` |
| `ADMIN_PASSWORD` | Contraseña propia de este portal, de al menos 16 caracteres |
| `TESSERA_WEBHOOK_SECRET` | Se obtiene al registrar el webhook en Tessera; se puede configurar después del primer despliegue |
| `TESSERA_API_BASE` | Opcional; predeterminado `https://tessera.blokis.dev/backend` |

No uses prefijos públicos como `NEXT_PUBLIC_` ni incrustes secretos en `public/`.
El acceso institucional solo pide `ADMIN_PASSWORD`: no reutiliza el login de
Tessera. Las cookies son HttpOnly y la sesión vence después de ocho horas.
Al cambiar variables en Vercel realiza **Redeploy** para aplicarlas.

## Configurar el webhook en Tessera

1. Copia el dominio **Production** real que Vercel asigne al portal.
2. Entra a Tessera con la cuenta institucional propietaria de la API key.
3. Abre **Integración → Webhooks → Crear webhook**.
4. En URL escribe `https://TU-DOMINIO.vercel.app/api/webhook`.
5. Selecciona `certificate.issued`, `certificate.failed` y
   `certificate.revoked`. Opcionalmente `credits.low_balance`.
6. Guarda el endpoint. Copia el secreto mostrado una sola vez.
7. En Vercel, Settings → Environment Variables, añade ese secreto como
   `TESSERA_WEBHOOK_SECRET` en Production y vuelve a desplegar.
8. Regresa a Tessera y pulsa **Probar**. Debe responder HTTP 200.
9. En Vercel → Logs, busca `Tessera: webhook firmado aceptado`.

El receptor `/api/webhook` necesita ser accesible desde Tessera sin una pantalla
de login de Vercel. Mantén el control de acceso del portal; si Deployment
Protection bloquea el receptor, configura una excepción apropiada para el
webhook o usa un dominio de producción públicamente accesible.

### Sin base de datos ni duplicados de negocio

La firma HMAC-SHA256 valida el cuerpo original y timestamps de hasta cinco
minutos. Se admiten tanto `{id,type,...}` de la prueba como
`{event,jobId,certificate,...}` de los eventos reales actuales. Los eventos
firmados se registran en los logs, sin almacenar datos del estudiante ni
ejecutar efectos secundarios: recibirlos otra vez no duplica certificados.
Los estados del portal vienen de consultas a Tessera; no se finge que un log
se almacena de forma persistente en memoria de Vercel. Si más adelante se
necesita enviar emails propios o matricular alumnos desde el webhook, habrá
que agregar una cola o registro durable con idempotencia.

La emisión conserva su idempotencyKey durante reintentos de los mismos datos.
El navegador guarda solo referencias y hashes en sessionStorage, no claves ni
datos personales de formularios. Un HTTP 202 significa «aceptado», no «emitido».
Polygon es la red principal y Avalanche la réplica; se muestra el estado de
cada una sin asumir que estén confirmadas.

## Guion breve de exposición

1. Abre el portal y verifica un certificado real por número o enlace de Tessera.
2. Muestra la imagen, el PDF, las redes y «Ver en Tessera».
3. Entra al área institucional con la contraseña del portal.
4. Consulta la lista y el saldo; selecciona una plantilla y completa un
   estudiante real de prueba. Emitir consume créditos reales.
5. Confirma la emisión, observa el progreso y abre el resultado al completarse.
6. Desde Tessera pulsa «Probar» en Webhooks y muestra la entrega 200 y los logs.

API: la institución solicita una acción. Webhook: Tessera notifica un evento.

## Verificación y emisión

Puedes verificar con número, UUID, enlace de Tessera (también el del QR con
`certificateId`), hash o enlace de una transacción de Polygon o Avalanche.
Una dirección de contrato identifica la colección, no un certificado concreto.
«Leer PDF o imagen» procesa hasta 12 MB y diez páginas en el dispositivo; los
archivos no se suben. «Escanear QR» usa la cámara con permiso y la detiene al
cerrar o cambiar de pestaña. Las bibliotecas oficiales PDF.js y jsQR se cargan
solo al usar estas opciones y se sirven desde este proyecto con sus licencias.
Leer el QR consulta la credencial original; no prueba la integridad del archivo
seleccionado. Compara su contenido con la imagen y PDF originales mostrados.

El formulario usa los campos y valores iniciales de la plantilla; mantiene los
datos mínimos exigidos por la API. Buscar por email es opcional y solo devuelve
estudiantes asociados a la institución, sin exponer el directorio global ni
wallets. Si no hay coincidencia se puede completar el nombre manualmente. La
API actual vincula la emisión al perfil por email y mantiene estas emisiones
externas bajo custodia institucional; este portal nunca envía una wallet manual.

La búsqueda institucional y los tipos de campos requieren desplegar también
la actualización de Tessera en `build2026`. La búsqueda por transacción incluye
las réplicas de Avalanche después de ese despliegue.

Si Vercel muestra un fallo de conexión, revisa que `TESSERA_API_BASE` sea
`https://tessera.blokis.dev/backend` (o elimina la variable para usar ese valor).
No pongas el dominio del portal ni una URL de login. Después realiza Redeploy.

## Verificación local del código

```sh
npm test
```

Las pruebas no requieren claves ni emiten certificados. No se inicia ningún
servidor local automáticamente.
