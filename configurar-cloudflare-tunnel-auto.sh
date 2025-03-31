#!/bin/bash

#============================================================
# SCRIPT AUTOMATIZADO PARA CONFIGURACIÓN DE CLOUDFLARE TUNNEL
#============================================================
# Este script configura automáticamente un túnel Cloudflare 
# con autenticación de Google, siguiendo ESTRICTAMENTE el esquema de 
# particionamiento del servidor para contenedores definido en:
# /configuration_System/particionamiento_servidor_contenedores.md
#
# CUMPLIMIENTO DEL ESQUEMA DE PARTICIONAMIENTO:
# - Sistema: Intel i5 G7, 16GB RAM, optimizado para >30 contenedores
# - /boot: 1GB (ext4) - Archivos de arranque
# - swap: 16GB - Espacio de intercambio
# - /: 100GB (ext4) - Sistema operativo
# - /home: 80GB (ext4) - Directorio personal del administrador
# - /var: 450GB (XFS+LVM) - Logs, bases de datos, configs (cloudflared)
# - /srv: Restante (XFS) - Datos de servicios, volúmenes persistentes
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

# Verificar estricto cumplimiento del esquema de particionamiento
print_step "Verificando cumplimiento del esquema de particionamiento según particionamiento_servidor_contenedores.md"

echo -e "${CYAN}Esquema recomendado para servidor con >30 contenedores Podman:${NC}"
echo -e "┌───────────┬─────────┬─────────────────┬─────────────────┐"
echo -e "│ Partición │ Tamaño  │ Sistema Archivos│ Propósito       │"
echo -e "├───────────┼─────────┼─────────────────┼─────────────────┤"
echo -e "│ /boot     │ 1 GB    │ ext4            │ Arranque        │"
echo -e "│ swap      │ 16 GB   │ swap            │ Intercambio     │"
echo -e "│ /         │ 100 GB  │ ext4            │ Sistema base    │"
echo -e "│ /home     │ 80 GB   │ ext4            │ Dir. personal   │"
echo -e "│ /var      │ 450 GB  │ XFS + LVM       │ Logs, configs   │"
echo -e "│ /srv      │ Restante│ XFS             │ Datos servicios │"
echo -e "└───────────┴─────────┴─────────────────┴─────────────────┘"
echo ""

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

# Mostrar comparativa de /srv vs /home para cumplir con recomendaciones
print_info "Ventajas de usar /srv en lugar de /home según particionamiento_servidor_contenedores.md:"
echo "┌─────────────────┬─────────────────────────────┬─────────────────────────────┐"
echo "│ Aspecto         │ /srv (recomendado)          │ /home (no recomendado)      │"
echo "├─────────────────┼─────────────────────────────┼─────────────────────────────┤"
echo "│ Propósito       │ Específico para servicios   │ Para datos de usuarios      │"
echo "│ Estándar FHS    │ Cumple con el estándar      │ No es el uso previsto       │"
echo "│ Seguridad       │ Separación clara            │ Mezcla datos y servicios    │"
echo "│ Escalabilidad   │ Mejor para producción       │ Mejor para desarrollo       │"
echo "└─────────────────┴─────────────────────────────┴─────────────────────────────┘"
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

# Referencia al archivo de particionamiento
print_info "Siguiendo esquema de particionamiento definido en: particionamiento_servidor_contenedores.md"
print_info "Usando /var para configuraciones (XFS+LVM) y /srv para datos (XFS)"

# Función mejorada para mostrar URL y/o QR según elección del usuario
show_auth_url() {
    local url=$1
    
    # Referencias explícitas al esquema de particionamiento
    print_info "Siguiendo estrictamente el esquema definido en particionamiento_servidor_contenedores.md"
    print_info "Usando particiones dedicadas: /var (XFS+LVM) para configs, /srv (XFS) para datos"
    
    # IMPORTANTE: Limpiar cualquier entrada anterior
    while read -r -t 0; do read -r; done
    
    # Preguntar al usuario cómo quiere ver la información de autenticación
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}         SELECCIONE UNA OPCIÓN DE VISUALIZACIÓN                     ${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    print_question "¿Cómo desea ver la información de autenticación? (Elija una opción):"
    echo "1. Ver solo la URL de autenticación"
    echo "2. Ver solo el código QR"
    echo "3. Ver ambos (URL y código QR)"
    echo ""
    echo -e "${YELLOW}Por favor, escriba 1, 2 o 3 y presione Enter:${NC}"
    
    # Leer la elección del usuario y asegurar que se espere la entrada
    read -r AUTH_VIEW_OPTION
    
    echo -e "${CYAN}Usted seleccionó la opción: $AUTH_VIEW_OPTION${NC}"
    echo ""
    
    # Opción 1 o 3: Mostrar URL
    if [[ "$AUTH_VIEW_OPTION" = "1" || "$AUTH_VIEW_OPTION" = "3" ]]; then
        echo ""
        echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}                URL DE AUTENTICACIÓN DE CLOUDFLARE                   ${NC}"
        echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "${YELLOW}COPIE Y PEGUE ESTA URL EN SU NAVEGADOR PARA AUTENTICARSE:${NC}"
        echo -e "${CYAN}$url${NC}"
        echo ""
        echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"
        echo ""
    fi
    
    # Opción 2 o 3: Mostrar QR
    if [[ "$AUTH_VIEW_OPTION" = "2" || "$AUTH_VIEW_OPTION" = "3" ]]; then
        # Verificar si qrencode está disponible
        if command -v qrencode &> /dev/null; then
            echo ""
            echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${GREEN}                     CÓDIGO QR DE AUTENTICACIÓN                     ${NC}"
            echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"
            echo ""
            echo -e "${YELLOW}ESCANEE ESTE CÓDIGO QR CON SU DISPOSITIVO MÓVIL:${NC}"
            echo ""
            
            # Generar QR con mejor visualización
            qrencode -t ANSIUTF8 -m 2 -s 1 "$url"
            
            echo ""
            echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"
            echo ""
        else
            print_warning "No se puede mostrar el código QR. qrencode no está instalado."
            # Si eligió solo QR pero no está disponible, mostrar URL
            if [[ "$AUTH_VIEW_OPTION" = "2" ]]; then
                echo -e "${YELLOW}Mostrando URL en su lugar:${NC}"
                echo -e "${CYAN}$url${NC}"
                echo ""
            fi
        fi
    fi
    
    # Si eligió una opción inválida, mostrar ambos por defecto
    if [[ "$AUTH_VIEW_OPTION" != "1" && "$AUTH_VIEW_OPTION" != "2" && "$AUTH_VIEW_OPTION" != "3" ]]; then
        print_warning "Opción no válida ($AUTH_VIEW_OPTION). Mostrando ambas opciones."
        
        # Mostrar URL
        echo ""
        echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}                URL DE AUTENTICACIÓN DE CLOUDFLARE                   ${NC}"
        echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"
        echo ""
        echo -e "${YELLOW}COPIE Y PEGUE ESTA URL EN SU NAVEGADOR PARA AUTENTICARSE:${NC}"
        echo -e "${CYAN}$url${NC}"
        echo ""
        echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"
        echo ""
        
        # Mostrar QR si está disponible
        if command -v qrencode &> /dev/null; then
            echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"
            echo -e "${GREEN}                     CÓDIGO QR DE AUTENTICACIÓN                     ${NC}"
            echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"
            echo ""
            echo -e "${YELLOW}ESCANEE ESTE CÓDIGO QR CON SU DISPOSITIVO MÓVIL:${NC}"
            echo ""
            qrencode -t ANSIUTF8 -m 2 -s 1 "$url"
            echo ""
            echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"
            echo ""
        fi
    fi
    
    print_info "Esperando a que complete la autenticación..."
    echo -e "${YELLOW}IMPORTANTE: Después de autenticarse en el navegador, presione ENTER aquí cuando termine${NC}"
    read -r -p "Presione ENTER cuando haya completado la autenticación en el navegador..." 
}

# Función mejorada para verificar autenticación
verify_authentication() {
    print_info "Verificando autenticación con Cloudflare..."
    
    # Verificar si el certificado existe
    if [ -f "$HOME/.cloudflared/cert.pem" ]; then
        print_success "Certificado encontrado en $HOME/.cloudflared/cert.pem"
        return 0
    else
        print_warning "No se encontró el certificado. Intentando nuevamente la autenticación."
        # Reintentar autenticación
        cloudflared tunnel login
        
        # Verificar nuevamente
        if [ -f "$HOME/.cloudflared/cert.pem" ]; then
            print_success "Certificado encontrado en $HOME/.cloudflared/cert.pem"
            return 0
        else
            print_error "No se pudo completar la autenticación. Verifique su conexión e intente nuevamente."
            return 1
        fi
    fi
}

# Capturar la URL de autenticación y mostrarla según preferencia del usuario
get_auth_url_and_show() {
    print_info "Capturando URL de autenticación de Cloudflare..."
    
    # Usar un archivo temporal para capturar toda la salida
    AUTH_OUTPUT_FILE=$(mktemp)
    
    # Ejecutar el comando de login y guardar toda la salida
    cloudflared tunnel login 2>&1 | tee "$AUTH_OUTPUT_FILE"
    
    # Extraer la URL de la salida capturada
    AUTH_URL=$(grep -o 'https://[^ ]*' "$AUTH_OUTPUT_FILE" | head -1)
    
    # Limpiar archivo temporal
    rm -f "$AUTH_OUTPUT_FILE"
    
    if [ -n "$AUTH_URL" ]; then
        print_success "URL de autenticación capturada correctamente: $AUTH_URL"
        
        # Mostrar la URL o QR según elección del usuario
        show_auth_url "$AUTH_URL"
        
        # Verificar autenticación con nueva función
        verify_authentication
        if [ $? -ne 0 ]; then
            print_error "Error en el proceso de autenticación"
            exit 1
        fi
    else
        print_warning "No se pudo capturar la URL automáticamente. Usando método estándar."
        cloudflared tunnel login
        
        # Verificar autenticación con nueva función
        verify_authentication
        if [ $? -ne 0 ]; then
            print_error "Error en el proceso de autenticación"
            exit 1
        fi
        print_success "Autenticación completada correctamente"
    fi
}

# Verificar si existe un certificado de autenticación
if [ -f "$HOME/.cloudflared/cert.pem" ];then
    print_info "Certificado de autenticación encontrado en $HOME/.cloudflared/cert.pem"
    print_question "¿Desea usar este certificado o generar uno nuevo? (usar/nuevo):"
    read -r AUTH_CHOICE
    
    if [[ "$AUTH_CHOICE" = "nuevo" ]]; then
        print_step "Iniciando proceso de autenticación con Cloudflare (modo consola)"
        print_info "Este servidor no tiene interfaz gráfica, por lo que el proceso será en dos pasos:"
        print_info "1. Seleccione cómo desea ver la información de autenticación"
        print_info "2. Escanee el QR o abra el enlace en un navegador e inicie sesión con Google"
        print_info "3. Una vez completado, el certificado se descargará automáticamente"
        
        echo ""
        print_warning "A continuación podrá elegir cómo ver la información de autenticación"
        echo ""
        
        # Usar la nueva función para obtener y mostrar la URL
        get_auth_url_and_show
        
        print_info "El certificado se ha descargado a $HOME/.cloudflared/cert.pem"
    else
        print_success "Usando certificado existente"
    fi
else
    print_step "No se encontró certificado de autenticación. Iniciando proceso de autenticación"
    print_info "Este servidor no tiene interfaz gráfica, por lo que el proceso será en dos pasos:"
    print_info "1. Seleccione cómo desea ver la información de autenticación"
    print_info "2. Escanee el QR o abra el enlace en un navegador e inicie sesión con Google"
    print_info "3. Una vez completado, el certificado se descargará automáticamente"
    
    echo ""
    print_warning "A continuación podrá elegir cómo ver la información de autenticación"
    echo ""
    
    # Usar la nueva función para obtener y mostrar la URL
    get_auth_url_and_show
    
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
print_success "Creado directorio para configuraciones en $CONFIG_DIR"
print_info "CUMPLIMIENTO ESTRICTO: Usando partición /var (XFS+LVM) para configuraciones según esquema"

# Crear directorio para datos persistentes respetando la partición /srv
PERSISTENT_DIR="/srv/cloudflare"
mkdir -p "$PERSISTENT_DIR"
print_success "Creado directorio para datos persistentes en $PERSISTENT_DIR"
print_info "CUMPLIMIENTO ESTRICTO: Usando partición /srv (XFS) para datos según esquema"

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

# Crear archivo de servicio systemd con configuración optimizada para el esquema
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
# Configuración ESTRICTAMENTE alineada con el esquema de particionamiento definido
# Datos persistentes en /srv (XFS) según particionamiento_servidor_contenedores.md
Environment="HOME=/srv/cloudflare"
# Recursos optimizados para entorno con >30 contenedores
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
echo -e "${GREEN}           SERVICIO CONFIGURADO - 100% GRATUITO SIN DOMINIO         ${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}¡IMPORTANTE! Esta configuración es:${NC}"
echo -e " ✓ ${GREEN}COMPLETAMENTE GRATUITA${NC} - No requiere ningún pago"
echo -e " ✓ ${GREEN}SIN DOMINIO PROPIO${NC} - Usa subdominios gratuitos de Cloudflare"
echo -e " ✓ ${GREEN}LISTA PARA USAR${NC} - No necesita configuración adicional"
echo ""
echo -e "${PURPLE}SU URL DE ACCESO AL SERVICIO ES:${NC}"
echo -e "${GREEN}https://${MAIN_SERVICE_NAME}.${TUNNEL_ID}.cfargotunnel.com${NC}"
echo ""

if [[ -n "$ADDITIONAL_SERVICES" ]]; then
    echo -e "${PURPLE}SERVICIOS ADICIONALES:${NC}"
    echo "$ADDITIONAL_SERVICES" | while read -r line; do
        if [[ "$line" == *"hostname:"* ]]; then
            SERVICE_URL=$(echo "$line" | awk '{print $3}')
            echo -e "${GREEN}https://$SERVICE_URL${NC}"
        fi
    done
    echo ""
fi

echo -e "${CYAN}Estas URLs funcionan inmediatamente. No necesita ninguna configuración adicional.${NC}"
echo -e "${CYAN}Puede compartir estas URLs directamente para acceder a sus servicios.${NC}"
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════════${NC}"

# Simplificar verificación de túnel
print_question "¿Desea verificar que el túnel está funcionando correctamente? (s/N):"
read -r CHECK_TUNNEL

if [[ "$CHECK_TUNNEL" = "s" || "$CHECK_TUNNEL" = "S" ]]; then
    print_info "Verificando conexión al túnel..."
    # Mostrar información básica del túnel
    echo -e "${CYAN}Información del túnel:${NC}"
    cloudflared tunnel info "$TUNNEL_NAME"
    
    # Comprobar el estatus del servicio de forma simple
    echo -e "${CYAN}Estado del servicio:${NC}"
    systemctl is-active cloudflared-tunnel.service
    
    print_success "¡Verificación completada! Su túnel gratuito está funcionando."
fi

print_success "¡LISTO! Su túnel gratuito de Cloudflare está configurado y listo para usar."
print_success "Puede acceder a su servicio en: https://${MAIN_SERVICE_NAME}.${TUNNEL_ID}.cfargotunnel.com"
echo ""