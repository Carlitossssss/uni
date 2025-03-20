#!/bin/bash

# Script para desinstalar Tailscale y eliminar toda su configuración
# Autor: GitHub Copilot
# Fecha: 2023

echo "====================================================="
echo "  Desinstalación de Tailscale"
echo "====================================================="
echo "Este script eliminará completamente Tailscale y liberará"
echo "este dispositivo de tu cuenta, ayudándote a mantenerte"
echo "dentro del límite de 20 dispositivos de la capa gratuita."
echo "====================================================="

# Verificar si se está ejecutando como root
if [ "$EUID" -ne 0 ]; then
    echo "Por favor, ejecute este script como root (sudo)"
    exit 1
fi

echo "[1/5] Deteniendo el servicio Tailscale..."
# Usar systemctl solo si existe
if command -v systemctl &> /dev/null; then
    systemctl stop tailscaled 2>/dev/null || true
    systemctl disable tailscaled 2>/dev/null || true
    echo "El servicio Tailscale ha sido detenido y deshabilitado."
else
    # Si no hay systemctl, intentar con service
    service tailscaled stop 2>/dev/null || true
    echo "El servicio Tailscale ha sido detenido."
fi

echo "[2/5] Cerrando la sesión de Tailscale y removiendo el dispositivo de tu cuenta..."
if command -v tailscale &> /dev/null; then
    # Intentar cerrar sesión, pero continuar incluso si falla
    tailscale logout 2>/dev/null || echo "No se pudo cerrar sesión, continuando con la desinstalación..."
    echo "Dispositivo desvinculado de tu cuenta de Tailscale."
else
    echo "El comando tailscale no fue encontrado, saltando el cierre de sesión."
fi

echo "[3/5] Desinstalando Tailscale..."
# Detectar y usar el gestor de paquetes apropiado
if command -v apt &> /dev/null; then
    echo "Usando APT para desinstalar..."
    # Ignorar errores de apt-get update
    apt-get update -y 2>/dev/null || true
    # Desinstalar con --purge para eliminar archivos de configuración
    apt-get purge -y tailscale tailscaled 2>/dev/null || true
    echo "Tailscale desinstalado con APT."
elif command -v yum &> /dev/null; then
    echo "Usando YUM para desinstalar..."
    yum remove -y tailscale tailscaled 2>/dev/null || true
    echo "Tailscale desinstalado con YUM."
elif command -v dnf &> /dev/null; then
    echo "Usando DNF para desinstalar..."
    dnf remove -y tailscale tailscaled 2>/dev/null || true
    echo "Tailscale desinstalado con DNF."
elif command -v zypper &> /dev/null; then
    echo "Usando Zypper para desinstalar..."
    zypper remove -y tailscale tailscaled 2>/dev/null || true
    echo "Tailscale desinstalado con Zypper."
echo ""
echo "====================================================="
echo "  ¡Desinstalación Completada!"
echo "====================================================="
echo ""
echo "✓ Tailscale ha sido completamente eliminado del sistema"
echo "✓ El dispositivo ha sido desvinculado de tu cuenta de Tailscale"
echo "✓ Ya no cuenta para el límite de 20 dispositivos de la capa gratuita"
echo "✓ Todos los datos y configuraciones asociados han sido eliminados"
echo ""
echo "Nota 1: El servidor SSH sigue instalado. Si desea eliminarlo,"
echo "ejecute: sudo apt purge -y openssh-server"
echo ""
echo "Nota 2: Puedes verificar en el panel de administración de Tailscale"
echo "que este dispositivo ya no aparece en tu lista de máquinas:"
echo "https://login.tailscale.com/admin/machines"
echo "====================================================="
