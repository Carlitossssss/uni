#!/bin/bash

# Script para instalar y configurar Tailscale automáticamente
# Autor: GitHub Copilot
# Fecha: 2023

echo "====================================================="
echo "  Instalación Automática de Tailscale para SSH"
echo "====================================================="

# Verificar si se está ejecutando como root
if [ "$EUID" -ne 0 ]; then
    echo "Por favor, ejecute este script como root (sudo)"
    exit 1
fi

# Clave de autenticación predefinida
DEFAULT_AUTH_KEY="tskey-auth-kk8erJ9qB811CNTRL-65DmAZXUzFMfSSfVudqrFMkNtVxxonaE"

echo "[1/5] Actualizando el sistema..."
apt update && apt upgrade -y

echo "[2/5] Instalando Tailscale..."
curl -fsSL https://tailscale.com/install.sh | bash

echo "[3/5] Verificando SSH..."
if ! dpkg -s openssh-server >/dev/null 2>&1; then
    echo "Instalando servidor SSH..."
    apt install -y openssh-server
fi

echo "[4/5] Iniciando y habilitando SSH..."
systemctl enable ssh
systemctl start ssh

echo "[5/5] Iniciando Tailscale..."
echo "Se iniciará el proceso de autenticación para este dispositivo."

# Verificar si Tailscale está en estado "stopped" - posiblemente por una ejecución cancelada
if tailscale status 2>&1 | grep -q "tailscaled is not running"; then
    echo "Reiniciando el servicio tailscaled después de una posible cancelación anterior..."
    systemctl restart tailscaled
    sleep 3
fi

# Verificar si ya está autenticado pero en estado problemático
TAILSCALE_STATUS=$(tailscale status 2>&1)
if [[ $? -ne 0 || $TAILSCALE_STATUS == *"Authentication required"* ]]; then
    echo "Detectada una sesión anterior incompleta. Limpiando estado..."
    tailscale down 2>/dev/null
    sleep 2
fi

# Verificar si ya está autenticado y preguntar si quiere reautenticar
if tailscale status 2>/dev/null | grep -q "authenticated"; then
    echo "Este dispositivo ya parece estar autenticado en Tailscale."
    read -p "¿Desea volver a autenticar? (s/N): " REAUTH
    if [[ ! $REAUTH =~ ^[Ss]$ ]]; then
        echo "Omitiendo la autenticación..."
    else
        # Detener Tailscale para reautenticarlo
        tailscale down
        sleep 2
    fi
fi

# Preguntar si usar la clave por defecto o elegir otra opción
echo "---------------------------------------------------"
echo "¿Desea utilizar la clave de autenticación por defecto?"
echo "1) Usar clave por defecto (recomendado)"
echo "2) Elegir otro método de autenticación"
read -p "Seleccione una opción (1-2, predeterminado: 1): " USE_DEFAULT
USE_DEFAULT=${USE_DEFAULT:-1}

if [ "$USE_DEFAULT" = "1" ]; then
    # Usar la clave de autenticación predefinida
    echo "Autenticando con la clave predefinida..."
    tailscale up --auth-key="$DEFAULT_AUTH_KEY"
    
    if [ $? -eq 0 ]; then
        echo "Autenticación con clave completada con éxito."
    else
        echo "Error durante la autenticación con clave predefinida."
        echo "La clave podría haber expirado o ser inválida."
        
        read -p "¿Desea probar con otro método de autenticación? (s/N): " TRY_OTHER
        if [[ ! $TRY_OTHER =~ ^[Ss]$ ]]; then
            echo "Cancelando proceso de autenticación."
            exit 1
        fi
        # Si decide probar otro método, caerá al else de abajo
        USE_DEFAULT="2"
    fi
fi

if [ "$USE_DEFAULT" = "2" ]; then
    # Preguntar método de autenticación
    echo "---------------------------------------------------"
    echo "Elija un método de autenticación:"
    echo "1) URL (método estándar)"
    echo "2) Código QR (requiere qrencode)"
    echo "3) Clave de autenticación (auth-key)"
    read -p "Seleccione una opción (1-3, predeterminado: 1): " AUTH_METHOD
    AUTH_METHOD=${AUTH_METHOD:-1}

    case $AUTH_METHOD in
        2)
            # Verificar si qrencode está instalado
            if ! command -v qrencode &> /dev/null; then
                echo "Instalando qrencode para generar el código QR..."
                apt install -y qrencode
            fi

            # Iniciar Tailscale con opción de código QR
            echo "Generando código QR para autenticación..."
            echo "Si escanea el código QR, se abrirá la URL de autenticación en su dispositivo móvil."
            tailscale up --qr | qrencode -t utf8
            echo "Escanee el código QR con su dispositivo móvil para autenticar."
            echo "Espere a que finalice la autenticación..."
            echo "Si el código QR es difícil de leer, puede usar el método de URL con la opción 1."
            ;;
        3)
            # Método de autenticación con clave
            echo "Utilizando autenticación con clave..."
            read -p "Introduzca la clave de autenticación (ejemplo: tskey-auth-xxx...): " AUTH_KEY
            
            if [[ -z "$AUTH_KEY" ]]; then
                echo "No se proporcionó una clave. Cancelando autenticación."
            else
                echo "Autenticando con la clave proporcionada..."
                tailscale up --auth-key="$AUTH_KEY"
                
                if [ $? -eq 0 ]; then
                    echo "Autenticación con clave completada con éxito."
                else
                    echo "Error durante la autenticación con clave. Verifique la clave e intente nuevamente."
                    exit 1
                fi
            fi
            ;;
        *)
            # Método de autenticación estándar con URL
            echo "Se abrirá una URL para autenticar el dispositivo."
            echo "Por favor, siga las instrucciones mostradas en la terminal para completar la autenticación."
            echo "---------------------------------------------------"
            echo "IMPORTANTE: Si cancela el proceso o tarda demasiado, puede volver a ejecutar"
            echo "el script y elegir nuevamente el método de autenticación sin problema."
            echo "---------------------------------------------------"
            
            # Intentar iniciar Tailscale con tiempo de espera
            timeout 180s tailscale up --reset
            
            # Verificar si el comando anterior tuvo éxito
            if [ $? -ne 0 ]; then
                echo "La autenticación no se completó en el tiempo esperado o fue cancelada."
                echo "Para intentarlo nuevamente, simplemente ejecute: sudo $(basename $0)"
                echo "No hay problema por cancelarlo ahora, puede reiniciarlo cuando lo desee."
                echo ""
                read -p "¿Desea intentar la autenticación una vez más ahora? (s/N): " RETRY
                if [[ $RETRY =~ ^[Ss]$ ]]; then
                    echo "Reintentando autenticación..."
                    tailscale up
                else
                    echo "Presione cualquier tecla para continuar con el resto del script..."
                    read -n 1
                fi
            else
                echo "Autenticación completada con éxito."
            fi
            ;;
    esac
fi

# Esperar un momento para que la conexión se establezca
echo "Esperando a que la conexión de Tailscale se establezca..."
sleep 5

# Verificar si Tailscale está funcionando correctamente
if ! tailscale status &>/dev/null; then
    echo "ADVERTENCIA: No se puede verificar el estado de Tailscale."
    echo ""
    echo "Si la autenticación falló, puede:"
    echo "1. Ejecutar este script nuevamente: sudo $(basename $0)"
    echo "2. O ejecutar manualmente: sudo tailscale up"
    echo ""
    read -p "¿Desea continuar de todas formas? (s/N): " CONTINUE
    if [[ ! $CONTINUE =~ ^[Ss]$ ]]; then
        echo "Script interrumpido. Vuelva a intentarlo cuando esté listo."
        exit 1
    fi
fi

# Obtener la dirección IP de Tailscale
TAILSCALE_IP=$(tailscale ip -4)

# Verificar si se obtuvo la IP correctamente
if [ -z "$TAILSCALE_IP" ]; then
    echo "No se pudo obtener la dirección IP de Tailscale."
    echo "Por favor, verifique el estado de Tailscale con: sudo tailscale status"
    exit 1
fi

echo ""
echo "====================================================="
echo "  ¡Instalación Completada!"
echo "====================================================="
echo ""
echo "La dirección IP de Tailscale de este servidor es: $TAILSCALE_IP"
echo ""
echo "Para conectarse por SSH desde otro dispositivo con Tailscale:"
echo "  ssh usuario@$TAILSCALE_IP"
echo ""
echo "Recuerde que debe instalar Tailscale en su computadora personal también"
echo "y usar la misma cuenta para autenticarse."
echo "====================================================="
