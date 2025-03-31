#!/bin/bash

#============================================================
# SCRIPT AUTOMATIZADO PARA CONFIGURACIÓN DE CLOUDFLARE TUNNEL
#============================================================
# Este script configura automáticamente un túnel Cloudflare 
# con autenticación de Google, siguiendo el esquema de 
# particionamiento del servidor para contenedores.
#
# CUMPLIMIENTO DEL ESQUEMA DE PARTICIONAMIENTO:
# - Configuraciones y logs: /var/lib/cloudflared (partición /var)
# - Datos persistentes de servicios: /srv/cloudflare (partición /srv)
# - Esquema optimizado para >30 contenedores Podman
#============================================================

# Colores para mejor visualización
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # Sin Color

# Función para imprimir mensajes con prefijo
print_step() {
    echo -e "${BLUE}[PASO]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[ÉXITO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[AVISO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_question() {
    echo -e "${PURPLE}[?]${NC} $1"
}

# Comprobar si se está ejecutando como root
if [ "$EUID" -ne 0 ]; then
    print_error "Este script debe ejecutarse como root"
    echo "Por favor, ejecute: sudo $0"
    exit 1
fi

# Mostrar banner
echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║                                                           ║"
echo "║   CONFIGURACIÓN AUTOMATIZADA DE CLOUDFLARE TUNNEL         ║"
echo "║   CON AUTENTICACIÓN GOOGLE                                ║"
echo "║                                                           ║"
echo "║   Optimizado para esquema de particionamiento:            ║"
echo "║   - Configs en /var (XFS + LVM)                           ║"
echo "║   - Datos persistentes en /srv (XFS)                      ║"
echo "║                                                           ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Verificar esquema de particionamiento recomendado
print_step "Verificando esquema de particionamiento del servidor"

# Verificar sistema de archivos para /srv (debe ser XFS)
SRV_FS=$(df -T /srv | awk 'NR==2 {print $2}')
if [ "$SRV_FS" = "xfs" ]; then
    print_success "Partición /srv usa sistema de archivos XFS (recomendado para datos persistentes)"
else
    print_warning "Partición /srv usa sistema de archivos $SRV_FS. Se recomienda XFS para mejor rendimiento con contenedores."
fi

# Verificar sistema de archivos para /var (debe ser XFS)
VAR_FS=$(df -T /var | awk 'NR==2 {print $2}')
if [ "$VAR_FS" = "xfs" ]; then
    print_success "Partición /var usa sistema de archivos XFS (recomendado para logs y configuraciones)"
else
    print_warning "Partición /var usa sistema de archivos $VAR_FS. Se recomienda XFS con LVM para mejor rendimiento."
fi

# Verificar si LVM está en uso para /var
if mount | grep /var | grep -q mapper; then
    print_success "Partición /var está usando LVM (recomendado para flexibilidad)"
else
    print_warning "Partición /var no parece usar LVM. Se recomienda LVM para mejor gestión del espacio."
fi

# Mostrar espacios disponibles
print_info "Espacio disponible en particiones principales:"
df -h /srv /var / | awk 'NR==1 || /^\// {print}'
echo ""

# Comprobar conexión a Internet
print_step "Verificando conexión a Internet"
if ! ping -c 1 cloudflare.com &> /dev/null; then
    print_error "No se puede conectar a Internet"
    exit 1
fi
print_success "Conexión a Internet disponible"

# Verificar si cloudflared está instalado
print_step "Verificando si cloudflared está instalado"
if command -v cloudflared &> /dev/null; then
    CLOUDFLARED_VERSION=$(cloudflared --version | head -n1 | cut -d " " -f 3)
    print_success "cloudflared ya está instalado (versión $CLOUDFLARED_VERSION)"
else
    print_info "cloudflared no está instalado. Instalando..."
    
    # Determinar arquitectura del sistema
    ARCH=$(dpkg --print-architecture)
    
    # Descargar e instalar cloudflared
    TMP_DIR=$(mktemp -d)
    cd "$TMP_DIR" || exit 1
    
    if [ "$ARCH" = "amd64" ]; then
        wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
        dpkg -i cloudflared-linux-amd64.deb
    elif [ "$ARCH" = "arm64" ]; then
        wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb
        dpkg -i cloudflared-linux-arm64.deb
    else
        print_error "Arquitectura no soportada: $ARCH"
        exit 1
    fi
    
    rm -rf "$TMP_DIR"
    
    # Verificar la instalación
    if command -v cloudflared &> /dev/null; then
        CLOUDFLARED_VERSION=$(cloudflared --version | head -n1 | cut -d " " -f 3)
        print_success "cloudflared instalado correctamente (versión $CLOUDFLARED_VERSION)"
    else
        print_error "No se pudo instalar cloudflared"
        exit 1
    fi
fi

# Verificar si qrencode está instalado (para generar códigos QR)
if ! command -v qrencode &> /dev/null; then
    print_info "Instalando qrencode para generar códigos QR..."
    apt-get update && apt-get install -y qrencode
    if ! command -v qrencode &> /dev/null; then
        print_warning "No se pudo instalar qrencode. Se mostrará solo la URL sin código QR."
    else
        print_success "qrencode instalado correctamente"
    fi
fi

# Función para mostrar URL como QR y texto
show_auth_url() {
    local url=$1
    echo -e "${YELLOW}URL de autenticación:${NC} $url"
    echo ""
    if command -v qrencode &> /dev/null; then
        print_info "Escanee el siguiente código QR con su dispositivo móvil:"
        echo ""
        # Aumentar el tamaño del QR para mejor visualización
        qrencode -t ANSIUTF8 -m 1 -o - "$url"
        echo ""
        print_info "Si el código QR no se muestra correctamente, utilice la URL directamente"
    fi
    print_info "O copie la URL y ábrala en su navegador"
}

# Verificar si existe un certificado de autenticación
if [ -f "$HOME/.cloudflared/cert.pem" ]; then
    print_info "Certificado de autenticación encontrado en $HOME/.cloudflared/cert.pem"
    print_question "¿Desea usar este certificado o generar uno nuevo? (usar/nuevo):"
    read -r AUTH_CHOICE
    
    if [[ "$AUTH_CHOICE" = "nuevo" ]]; then
        print_step "Iniciando proceso de autenticación con Cloudflare (modo consola)"
        print_info "Este servidor no tiene interfaz gráfica, por lo que el proceso será en dos pasos:"
        print_info "1. Se mostrará un código QR y un enlace de autenticación"
        print_info "2. Escanee el QR o abra el enlace en un navegador e inicie sesión con Google"
        print_info "3. Una vez completado, el certificado se descargará automáticamente"
        
        echo ""
        print_warning "A continuación se generará la autenticación. Utilice el código QR o la URL:"
        echo ""
        
        # Capturar la URL de autenticación y mostrarla como QR
        AUTH_URL=$(cloudflared tunnel login 2>&1 | grep -o 'https://[^ ]*' | head -1)
        
        if [ -n "$AUTH_URL" ]; then
            show_auth_url "$AUTH_URL"
            # Esperar a que el usuario complete la autenticación
            print_info "Esperando que complete la autenticación..."
            while [ ! -f "$HOME/.cloudflared/cert.pem" ] || [ "$(find "$HOME/.cloudflared/cert.pem" -mmin -5 | wc -l)" -eq 0 ]; do
                sleep 5
            done
            print_success "Autenticación completada correctamente"
        else
            # Si no podemos capturar la URL, usamos el método estándar
            cloudflared tunnel login
            if [ $? -ne 0 ]; then
                print_error "Error en el proceso de autenticación"
                exit 1
            fi
            print_success "Autenticación completada correctamente"
        fi
        
        print_info "El certificado se ha descargado a $HOME/.cloudflared/cert.pem"
    else
        print_success "Usando certificado existente"
    fi
else
    print_step "No se encontró certificado de autenticación. Iniciando proceso de autenticación"
    print_info "Este servidor no tiene interfaz gráfica, por lo que el proceso será en dos pasos:"
    print_info "1. Se mostrará un código QR y un enlace de autenticación"
    print_info "2. Escanee el QR o abra el enlace en un navegador e inicie sesión con Google"
    print_info "3. Una vez completado, el certificado se descargará automáticamente"
    
    echo ""
    print_warning "A continuación se generará la autenticación. Utilice el código QR o la URL:"
    echo ""
    
    # Capturar la URL de autenticación y mostrarla como QR
    AUTH_URL=$(cloudflared tunnel login 2>&1 | grep -o 'https://[^ ]*' | head -1)
    
    if [ -n "$AUTH_URL" ]; then
        show_auth_url "$AUTH_URL"
        # Esperar a que el usuario complete la autenticación
        print_info "Esperando que complete la autenticación..."
        while [ ! -f "$HOME/.cloudflared/cert.pem" ] || [ "$(find "$HOME/.cloudflared/cert.pem" -mmin -5 | wc -l)" -eq 0 ]; do
            sleep 5
        done
        print_success "Autenticación completada correctamente"
    else
        # Si no podemos capturar la URL, usamos el método estándar
        cloudflared tunnel login
        if [ $? -ne 0 ]; then
            print_error "Error en el proceso de autenticación"
            exit 1
        fi
        print_success "Autenticación completada correctamente"
    fi
    
    print_info "El certificado se ha descargado a $HOME/.cloudflared/cert.pem"
fi

# Solicitar información para el túnel
echo ""
print_question "Por favor, introduzca un nombre para su túnel (por ejemplo: mi-servidor):"
read -r TUNNEL_NAME

# Verificar si el túnel ya existe
EXISTING_TUNNEL=$(cloudflared tunnel list 2>/dev/null | grep -w "$TUNNEL_NAME")
if [[ -n "$EXISTING_TUNNEL" ]]; then
    print_warning "Ya existe un túnel con el nombre '$TUNNEL_NAME'"
    print_question "¿Desea usar este túnel existente o crear uno nuevo? (usar/nuevo):"
    read -r TUNNEL_CHOICE
    
    if [[ "$TUNNEL_CHOICE" = "nuevo" ]]; then
        print_question "Por favor, introduzca un nombre diferente para su túnel:"
        read -r TUNNEL_NAME
        print_step "Creando nuevo túnel '$TUNNEL_NAME'..."
        cloudflared tunnel create "$TUNNEL_NAME"
    else
        print_success "Usando túnel existente '$TUNNEL_NAME'"
    fi
else
    print_step "Creando nuevo túnel '$TUNNEL_NAME'..."
    cloudflared tunnel create "$TUNNEL_NAME"
fi

# Obtener ID del túnel
TUNNEL_ID=$(cloudflared tunnel list | grep -w "$TUNNEL_NAME" | awk '{print $1}')
if [[ -z "$TUNNEL_ID" ]]; then
    print_error "No se pudo obtener el ID del túnel. Por favor, verifique si se creó correctamente."
    exit 1
fi

print_success "Túnel creado/encontrado con ID: $TUNNEL_ID"

# Configurar puertos y servicios a exponer
echo ""
print_info "Ahora configuraremos los servicios que desea exponer a través del túnel."
print_info "Según el esquema de particionamiento recomendado:"
print_info " - Configuraciones se almacenan en /var/lib/cloudflared (partición /var)"
print_info " - Datos persistentes deben almacenarse en /srv (partición /srv)"
print_info " - Sistema de archivos XFS para óptimo rendimiento con contenedores"

# Solicitar información sobre el puerto principal (con 3000 como valor predeterminado)
print_question "¿Qué puerto desea exponer como servicio principal? (predeterminado: 3000):"
read -r MAIN_PORT
MAIN_PORT=${MAIN_PORT:-3000}

# Preguntar por un nombre para el servicio principal
print_question "Introduzca un nombre para este servicio (por ejemplo: dashboard, app, etc.):"
read -r MAIN_SERVICE_NAME

# Preguntar si desea configurar más servicios
print_question "¿Desea exponer servicios adicionales? (s/N):"
read -r MORE_SERVICES
ADDITIONAL_SERVICES=""

if [[ "$MORE_SERVICES" = "s" || "$MORE_SERVICES" = "S" ]]; then
    CONTINUE_ADDING="s"
    
    while [[ "$CONTINUE_ADDING" = "s" || "$CONTINUE_ADDING" = "S" ]]; do
        print_question "Introduzca un nombre para el servicio adicional:"
        read -r SERVICE_NAME
        
        print_question "¿Qué puerto local utiliza este servicio?:"
        read -r SERVICE_PORT
        
        ADDITIONAL_SERVICES="${ADDITIONAL_SERVICES}  - hostname: ${SERVICE_NAME}.${TUNNEL_ID}.cfargotunnel.com
    service: http://localhost:${SERVICE_PORT}
"
        
        print_question "¿Desea añadir otro servicio? (s/N):"
        read -r CONTINUE_ADDING
    done
fi

# Crear directorio para archivos de configuración respetando la partición /var
CONFIG_DIR="/var/lib/cloudflared"
mkdir -p "$CONFIG_DIR"
print_success "Creado directorio para configuraciones en $CONFIG_DIR (partición /var)"
print_info "Esto cumple con el esquema recomendado de usar /var para configuraciones"

# Crear directorio para datos persistentes respetando la partición /srv
PERSISTENT_DIR="/srv/cloudflare"
mkdir -p "$PERSISTENT_DIR"
print_success "Creado directorio para datos persistentes en $PERSISTENT_DIR (partición /srv)"
print_info "Esto cumple con el esquema recomendado de usar /srv para datos de servicios"

# Crear archivo de configuración
print_step "Creando archivo de configuración en $CONFIG_DIR/config.yml"

cat > "$CONFIG_DIR/config.yml" << EOF
# Configuración del túnel Cloudflare
# Generado automáticamente por script
# Siguiendo esquema de particionamiento optimizado para contenedores

tunnel: $TUNNEL_ID
credentials-file: $HOME/.cloudflared/${TUNNEL_ID}.json

# Configuración de entrada
ingress:
  # Servicio principal
  - hostname: ${MAIN_SERVICE_NAME}.${TUNNEL_ID}.cfargotunnel.com
    service: http://localhost:${MAIN_PORT}
${ADDITIONAL_SERVICES}
  # Configuración predeterminada para solicitudes no coincidentes
  - service: http_status:404
EOF

print_success "Archivo de configuración creado correctamente"

# Configurar el túnel para ejecutarse como servicio del sistema
print_step "Configurando túnel como servicio del sistema"

# Crear archivo de servicio systemd con configuración optimizada
cat > /etc/systemd/system/cloudflared-tunnel.service << EOF
[Unit]
Description=Cloudflare Tunnel for $TUNNEL_NAME
After=network.target
Documentation=https://developers.cloudflare.com/cloudflare-one/connections/connect-apps

[Service]
Type=simple
User=root
ExecStart=/usr/bin/cloudflared tunnel --config $CONFIG_DIR/config.yml run
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
# Configuración optimizada para el esquema de particionamiento
Environment="HOME=/srv/cloudflare"
# Establecer límites de recursos
CPUQuota=25%
MemoryLimit=512M

[Install]
WantedBy=multi-user.target
EOF

# Recargar systemd, habilitar e iniciar el servicio
systemctl daemon-reload
systemctl enable cloudflared-tunnel.service
systemctl start cloudflared-tunnel.service

# Verificar el estado del servicio
if systemctl is-active --quiet cloudflared-tunnel.service; then
    print_success "Servicio cloudflared-tunnel iniciado correctamente"
else
    print_error "Error al iniciar el servicio cloudflared-tunnel"
    print_info "Verifique el estado con: systemctl status cloudflared-tunnel.service"
    exit 1
fi

# Configurar autenticación con Google para los servicios
print_step "Configurando autenticación con Google para los servicios expuestos"

print_info "Para completar la configuración de autenticación con Google:"
print_info "1. Acceda al panel de Cloudflare Zero Trust: https://one.dash.cloudflare.com/"
print_info "2. Navegue a 'Access' > 'Applications'"
print_info "3. Haga clic en 'Add an application'"
print_info "4. Seleccione 'Self-hosted'"
print_info "5. Nombre la aplicación: '$MAIN_SERVICE_NAME'"
print_info "6. En la URL, introduzca: https://${MAIN_SERVICE_NAME}.${TUNNEL_ID}.cfargotunnel.com"
print_info "7. En las políticas de acceso, seleccione 'Google' como proveedor de identidad"
print_info "8. Especifique los dominios o correos permitidos"
print_info "9. Guarde la configuración"

print_success "Configuración de túnel completada con éxito"

# Mostrar información de acceso
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}                INFORMACIÓN DE ACCESO A LOS SERVICIOS${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "Servicio principal (${MAIN_SERVICE_NAME}):"
echo -e "  ${CYAN}https://${MAIN_SERVICE_NAME}.${TUNNEL_ID}.cfargotunnel.com${NC}"
echo -e "  Expone el servicio local en el puerto: ${MAIN_PORT}"
echo ""

if [[ -n "$ADDITIONAL_SERVICES" ]]; then
    echo -e "Servicios adicionales:"
    echo "$ADDITIONAL_SERVICES" | while read -r line; do
        if [[ "$line" == *"hostname:"* ]]; then
            SERVICE_URL=$(echo "$line" | awk '{print $3}')
            echo -e "  ${CYAN}https://$SERVICE_URL${NC}"
        elif [[ "$line" == *"service:"* ]]; then
            SERVICE_PORT=$(echo "$line" | awk '{print $3}' | cut -d':' -f3)
            echo -e "  Expone el servicio local en el puerto: $SERVICE_PORT"
            echo ""
        fi
    done
fi

echo -e "${YELLOW}IMPORTANTE:${NC} Para acceder a estos servicios, los usuarios deberán autenticarse"
echo -e "con sus cuentas de Google una vez que configure la aplicación en Cloudflare Zero Trust."
echo ""
echo -e "Comandos útiles:"
echo -e "  - Ver estado del servicio: ${CYAN}systemctl status cloudflared-tunnel.service${NC}"
echo -e "  - Ver logs del túnel: ${CYAN}journalctl -u cloudflared-tunnel.service -f${NC}"
echo -e "  - Reiniciar el túnel: ${CYAN}systemctl restart cloudflared-tunnel.service${NC}"
echo ""
echo -e "${YELLOW}RECOMENDACIONES SEGÚN ESQUEMA DE PARTICIONAMIENTO:${NC}"
echo -e "  - Almacene los volúmenes persistentes de contenedores en: ${CYAN}/srv/[servicio]${NC}"
echo -e "  - Mantenga las configuraciones de servicios en: ${CYAN}/var/lib/[servicio]${NC}"
echo -e "  - Para optimizar rendimiento, todos los servicios expuestos a través del túnel"
echo -e "    deben almacenar sus datos en la partición ${CYAN}/srv${NC} (XFS) en lugar de ${CYAN}/home${NC}"
echo -e "  - Se recomienda usar partición ${CYAN}/var${NC} con XFS y LVM para mejor rendimiento"
echo -e "    con los logs y configuraciones de los contenedores"
echo -e "  - Referencia completa: ${CYAN}particionamiento_servidor_contenedores.md${NC}"
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"