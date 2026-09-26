#!/usr/bin/env bash
#
# setup_vm.sh
#
# Provisiona una VM Ubuntu con:
#   - Escritorio XFCE + XRDP (acceso remoto gráfico)
#   - Usuario de trabajo con home apuntando a ~/Desktop en shells interactivas
#   - Herramientas de desarrollo en C/C++ y depuración
#     (gcc, gdb, valgrind, strace, htop, cron, etc.)
#   - Nginx + Certbot (HTTPS con Let's Encrypt) sobre un dominio propio
#   - File Browser Quantum servido tras ese Nginx, para subir/bajar archivos
#     sin necesidad de SSH ni RDP
#
# Pensado para Ubuntu 26.04 LTS recién instalado, ejecutándose como root
# (o con sudo) en la propia máquina.
#
# Uso:
#   1. Edita las variables de configuración de la sección siguiente.
#   2. sudo bash setup_vm.sh
#
# El script es idempotente en la medida de lo posible: puedes volver a
# ejecutarlo si algo falla a mitad de camino.

set -euo pipefail

# ============================================================
# VARIABLES DE CONFIGURACIÓN — EDITA ESTO ANTES DE EJECUTAR
# ============================================================

# Usuario de trabajo que se creará en el sistema (no root).
# Será el usuario para SSH, RDP y el propietario del File Browser.
NEW_USER="johndoe"

# Contraseña del usuario del sistema (SSH / RDP).
# Déjala vacía ("") para que el script te la pida de forma interactiva
# y no quede escrita en este fichero.
NEW_USER_PASSWORD=""

# Dominio que ya apunta (registro A) a la IP pública de este servidor.
DOMAIN="os.ejemplo.eu"

# Email de contacto para Let's Encrypt (avisos de caducidad, etc.)
LETSENCRYPT_EMAIL="tu_email@ejemplo.com"

# Puerto interno donde escuchará File Browser Quantum (detrás de Nginx).
FILEBROWSER_PORT="8080"

# ============================================================
# NO HACE FALTA EDITAR NADA A PARTIR DE AQUÍ
# ============================================================

log() {
    echo -e "\n\033[1;32m==>\033[0m \033[1m$1\033[0m"
}

warn() {
    echo -e "\033[1;33m[AVISO]\033[0m $1"
}

die() {
    echo -e "\033[1;31m[ERROR]\033[0m $1" >&2
    exit 1
}

if [[ $EUID -ne 0 ]]; then
    die "Este script debe ejecutarse como root (usa: sudo bash setup_vm_so.sh)"
fi

if [[ -z "$NEW_USER_PASSWORD" ]]; then
    echo "Introduce la contraseña para el usuario '$NEW_USER' (SSH/RDP):"
    read -rs NEW_USER_PASSWORD
    echo
    if [[ -z "$NEW_USER_PASSWORD" ]]; then
        die "La contraseña no puede estar vacía."
    fi
fi

# ------------------------------------------------------------
# 1. Actualización del sistema
# ------------------------------------------------------------
log "1/8 Actualizando el sistema"
apt update && apt upgrade -y

# ------------------------------------------------------------
# 2. Crear usuario de trabajo
# ------------------------------------------------------------
log "2/8 Creando usuario '$NEW_USER'"
if id "$NEW_USER" &>/dev/null; then
    warn "El usuario '$NEW_USER' ya existe, se omite la creación."
else
    adduser --disabled-password --gecos "" "$NEW_USER"
    echo "${NEW_USER}:${NEW_USER_PASSWORD}" | chpasswd
    usermod -aG sudo "$NEW_USER"
fi

USER_HOME="/home/${NEW_USER}"

# ------------------------------------------------------------
# 3. Escritorio XFCE + XRDP
# ------------------------------------------------------------
log "3/8 Instalando XFCE y XRDP"
apt install -y xfce4 xfce4-goodies xrdp

echo "xfce4-session" > "${USER_HOME}/.xsession"
chown "${NEW_USER}:${NEW_USER}" "${USER_HOME}/.xsession"

adduser xrdp ssl-cert || true

systemctl enable xrdp
systemctl restart xrdp

# ------------------------------------------------------------
# 4. Herramientas de desarrollo y administración del sistema
# ------------------------------------------------------------
log "4/8 Instalando herramientas de desarrollo y administración"

# Compilación y depuración en C
apt install -y build-essential gdb valgrind manpages-dev

# Trazado de llamadas al sistema
apt install -y strace ltrace

# Monitorización del sistema
apt install -y htop sysstat iotop procps

# Administración y automatización
apt install -y cron rsyslog acl

# Editores
apt install -y vim nano

# Utilidades varias
apt install -y net-tools lsof tree curl

# ------------------------------------------------------------
# 5. Home de trabajo en ~/Desktop para shells interactivas
# ------------------------------------------------------------
log "5/8 Configurando ~/Desktop como directorio de trabajo por defecto"

mkdir -p "${USER_HOME}/Desktop"
chown "${NEW_USER}:${NEW_USER}" "${USER_HOME}/Desktop"

BASHRC="${USER_HOME}/.bashrc"
MARKER="# Ir directamente a Desktop al iniciar sesión"
if ! grep -qF "$MARKER" "$BASHRC" 2>/dev/null; then
    {
        echo ""
        echo "$MARKER"
        echo "cd ~/Desktop"
    } >> "$BASHRC"
fi
chown "${NEW_USER}:${NEW_USER}" "$BASHRC"

# ------------------------------------------------------------
# 6. Nginx + Certbot (HTTPS)
# ------------------------------------------------------------
log "6/8 Instalando Nginx y Certbot"
apt install -y nginx certbot python3-certbot-nginx

cat > /etc/nginx/sites-available/filebrowser <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    location / {
        proxy_pass http://127.0.0.1:${FILEBROWSER_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        client_max_body_size 0;
        proxy_read_timeout 300s;
    }
}
EOF

ln -sf /etc/nginx/sites-available/filebrowser /etc/nginx/sites-enabled/filebrowser
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl restart nginx

log "Solicitando certificado HTTPS para ${DOMAIN}"
warn "Asegúrate de que el DNS de ${DOMAIN} ya apunta a la IP de este servidor"
warn "y de que los puertos 80 y 443 están abiertos en el firewall antes de continuar."

if certbot --nginx -d "${DOMAIN}" --non-interactive --agree-tos -m "${LETSENCRYPT_EMAIL}" --redirect; then
    log "Certificado HTTPS instalado correctamente."
else
    warn "Certbot ha fallado. Puedes reintentarlo manualmente más tarde con:"
    warn "  sudo certbot --nginx -d ${DOMAIN}"
fi

# ------------------------------------------------------------
# 7. File Browser Quantum
# ------------------------------------------------------------
log "7/8 Instalando File Browser Quantum"

curl -fsSL "https://github.com/gtsteffaniak/filebrowser/releases/latest/download/linux-amd64-filebrowser" -o /usr/local/bin/filebrowser
chmod +x /usr/local/bin/filebrowser

mkdir -p /etc/filebrowser/cache

cat > /etc/filebrowser/config.yaml <<EOF
server:
  port: ${FILEBROWSER_PORT}
  database: /etc/filebrowser/database.db
  cacheDir: /etc/filebrowser/cache
  sources:
    - path: ${USER_HOME}
auth:
  methods:
    password:
      enabled: true
EOF

chown -R "${NEW_USER}:${NEW_USER}" /etc/filebrowser

cat > /etc/systemd/system/filebrowser.service <<EOF
[Unit]
Description=File Browser Quantum
After=network.target

[Service]
User=${NEW_USER}
ExecStart=/usr/local/bin/filebrowser -c /etc/filebrowser/config.yaml
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable filebrowser
systemctl restart filebrowser

sleep 2

# ------------------------------------------------------------
# 8. Resumen final
# ------------------------------------------------------------
log "8/8 Instalación completa"

echo ""
echo "=================================================================="
echo " RESUMEN"
echo "=================================================================="
echo " Usuario del sistema (SSH / RDP) : ${NEW_USER}"
echo " Home                            : ${USER_HOME}"
echo " Directorio de trabajo por defecto: ${USER_HOME}/Desktop"
echo ""
echo " Acceso SSH   : ssh ${NEW_USER}@${DOMAIN}"
echo " Acceso RDP   : ${DOMAIN}  (puerto 3389, usuario ${NEW_USER})"
echo " Gestor de archivos web: https://${DOMAIN}"
echo ""
echo " IMPORTANTE - File Browser Quantum:"
echo "   El primer arranque crea un usuario admin por defecto con"
echo "   credenciales admin/admin. Entra en https://${DOMAIN},"
echo "   cambia esa contraseña inmediatamente y crea tu propio usuario"
echo "   '${NEW_USER}' desde Settings -> User Management."
echo "=================================================================="
echo ""
echo " Pendiente de verificar manualmente:"
echo "   1. El firewall (Hetzner Cloud Firewall u otro) permite entrada"
echo "      en los puertos 22 (SSH), 3389 (RDP), 80 y 443 (HTTP/HTTPS)."
echo "   2. El registro DNS tipo A de '${DOMAIN}' apunta a la IP de este"
echo "      servidor (modo 'DNS only' si usas Cloudflare, sin proxy)."
echo "   3. Cambiar la contraseña admin/admin de File Browser Quantum."
echo "=================================================================="