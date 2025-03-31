#!/bin/bash

# Script para configurar la estructura de carpetas para servidor de despliegue con Podman
# Basado en la estructura recomendada en estructura_servidor_podman.md

# Colores para mensajes
VERDE='\033[0;32m'
AMARILLO='\033[1;33m'
ROJO='\033[0;31m'
NC='\033[0m' # No Color

# Verificar si se está ejecutando como root
if [ "$EUID" -ne 0 ]; then
    echo -e "${ROJO}Este script debe ejecutarse como root${NC}"
    echo "Por favor, ejecute: sudo bash $0"
    exit 1
fi

echo -e "${VERDE}=== Configuración de Estructura para Servidor de Contenedores ===${NC}"
echo "Este script configurará la estructura de directorios recomendada"
echo "para un servidor de despliegue con Podman."
echo

# Función para crear directorios con mensajes
crear_directorio() {
    mkdir -p "$1"
    if [ $? -eq 0 ]; then
        echo -e "${VERDE}✓${NC} Creado: $1"
    else
        echo -e "${ROJO}✗${NC} Error al crear: $1"
        exit 1
    fi
}

echo -e "${AMARILLO}Paso 1: Creando estructura principal de directorios...${NC}"
# Estructura en /var/lib/podman
crear_directorio "/var/lib/podman"

# Estructura en /srv
crear_directorio "/srv/repos"
crear_directorio "/srv/apps"
crear_directorio "/srv/datos/db"
crear_directorio "/srv/datos/files"
crear_directorio "/srv/config/nginx"
crear_directorio "/srv/config/ssl"

echo -e "${AMARILLO}Paso 2: Configurando Podman...${NC}"
# Verificar si el directorio de configuración existe
crear_directorio "/etc/containers"

# Crear configuración de storage para Podman
cat > /etc/containers/storage.conf << 'EOF'
[storage]
  driver = "overlay"
  graphroot = "/var/lib/podman"

[engine]
  volume_path = "/srv/datos"
EOF

echo -e "${VERDE}✓${NC} Configuración de Podman guardada en /etc/containers/storage.conf"

echo -e "${AMARILLO}Paso 3: Creando archivos de ejemplo para despliegues...${NC}"

# Crear un archivo de ejemplo podman-compose.yml
cat > /srv/apps/ejemplo-app.yml << 'EOF'
version: '3'
services:
  app:
    image: nginx:latest
    container_name: app-ejemplo
    ports:
      - "127.0.0.1:8080:80"
    volumes:
      - /srv/repos/ejemplo:/usr/share/nginx/html:ro
    restart: unless-stopped

  db:
    image: mariadb:latest
    container_name: db-ejemplo
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_ROOT_PASSWORD}
      MYSQL_DATABASE: ejemplo
      MYSQL_USER: ${DB_USER}
      MYSQL_PASSWORD: ${DB_PASSWORD}
    volumes:
      - /srv/datos/db/ejemplo:/var/lib/mysql
    restart: unless-stopped
EOF

# Crear un archivo .env de ejemplo
cat > /srv/apps/.env.ejemplo << 'EOF'
# Variables de entorno para el despliegue
DB_ROOT_PASSWORD=cambia_esta_contraseña
DB_USER=usuario_app
DB_PASSWORD=contraseña_segura
EOF

# Crear un script de despliegue de ejemplo
cat > /srv/apps/deploy-ejemplo.sh << 'EOF'
#!/bin/bash

# Script de ejemplo para desplegar una aplicación
APP_NAME="ejemplo"
REPO_URL="https://github.com/usuario/ejemplo.git"

# 1. Clonar/actualizar repositorio
if [ -d "/srv/repos/$APP_NAME" ]; then
  echo "Actualizando repositorio existente..."
  cd "/srv/repos/$APP_NAME"
  git pull
else
  echo "Clonando repositorio..."
  git clone "$REPO_URL" "/srv/repos/$APP_NAME"
fi

# 2. Desplegar con podman-compose
cd "/srv/apps"
cp .env.ejemplo .env  # En producción, usar un .env específico y seguro

# 3. Iniciar contenedores
podman-compose -f ejemplo-app.yml up -d

echo "Despliegue completado. La aplicación está disponible en http://localhost:8080"
EOF

# Hacer ejecutable el script de despliegue
chmod +x /srv/apps/deploy-ejemplo.sh

echo -e "${AMARILLO}Paso 4: Estableciendo permisos adecuados...${NC}"
# Asegurar permisos apropiados
chown -R root:root /srv/config
chmod -R 755 /srv/config

# Permisos para datos (restritos pero utilizables por Podman)
chown -R root:root /srv/datos
chmod -R 755 /srv/datos
chmod -R 777 /srv/datos/db  # Permisivo para las bases de datos (ajustar según necesidades de seguridad)

# Permisos para aplicaciones y repos
chown -R root:root /srv/apps /srv/repos
chmod -R 755 /srv/apps /srv/repos

echo -e "${AMARILLO}Paso 5: Creando script para monitoreo básico...${NC}"
# Crear un script de monitoreo simple
cat > /usr/local/bin/monitorear-contenedores.sh << 'EOF'
#!/bin/bash

echo "=== Estado de los Contenedores ==="
podman ps -a --format "{{.Names}}\t{{.Status}}\t{{.Ports}}"

echo -e "\n=== Uso de Recursos ==="
echo "CPU y Memoria:"
podman stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"

echo -e "\n=== Espacio en Disco ==="
df -h /var /srv
EOF

chmod +x /usr/local/bin/monitorear-contenedores.sh

echo -e "${AMARILLO}Paso 6: Configurando tarea programada para mantenimiento...${NC}"
# Crear un script de mantenimiento
cat > /usr/local/bin/mantenimiento-podman.sh << 'EOF'
#!/bin/bash

# Limpiar recursos sin usar
podman system prune --force

# Backup de configuraciones
FECHA=$(date +%Y%m%d)
mkdir -p /srv/backups/config/$FECHA
cp -r /srv/config/* /srv/backups/config/$FECHA/

# Mantener solo los últimos 7 backups
find /srv/backups/config -type d -mtime +7 -exec rm -rf {} \; 2>/dev/null || true

echo "Mantenimiento completado: $(date)"
EOF

chmod +x /usr/local/bin/mantenimiento-podman.sh

# Configurar cron para ejecutar el mantenimiento
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/mantenimiento-podman.sh > /var/log/podman-mantenimiento.log 2>&1") | crontab -

# Crear directorio de backups si no existe
crear_directorio "/srv/backups/config"

echo -e "\n${VERDE}=== ¡Configuración completada! ===${NC}"
echo
echo "Estructura de directorios creada:"
echo "  • /var/lib/podman - Almacenamiento principal de Podman"
echo "  • /srv/repos      - Repositorios de código fuente"
echo "  • /srv/apps       - Configuraciones de despliegue"
echo "  • /srv/datos      - Datos persistentes (DB, archivos)"
echo "  • /srv/config     - Configuraciones globales"
echo "  • /srv/backups    - Backups automáticos"
echo
echo "Archivos de ejemplo creados:"
echo "  • /srv/apps/ejemplo-app.yml - Ejemplo de podman-compose"
echo "  • /srv/apps/.env.ejemplo    - Ejemplo de variables de entorno"
echo "  • /srv/apps/deploy-ejemplo.sh - Script de despliegue de ejemplo"
echo
echo "Scripts de utilidad:"
echo "  • /usr/local/bin/monitorear-contenedores.sh - Monitoreo básico"
echo "  • /usr/local/bin/mantenimiento-podman.sh - Mantenimiento programado (diariamente a las 2 AM)"
echo
echo -e "${AMARILLO}Para desplegar su primera aplicación:${NC}"
echo "  1. Personalice los archivos de ejemplo en /srv/apps"
echo "  2. Clone su repositorio en /srv/repos"
echo "  3. Ejecute un script de despliegue similar al ejemplo"
echo
echo -e "${VERDE}¡Todo listo para comenzar a desplegar contenedores!${NC}"

# Detectar si es la primera ejecución en Podman
if ! command -v podman &> /dev/null; then
    echo -e "${AMARILLO}AVISO: Podman no está instalado en este sistema.${NC}"
    echo "Instale Podman con el siguiente comando:"
    echo "  apt update && apt install -y podman"
fi
