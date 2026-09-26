# VM Ubuntu con escritorio remoto

Script de aprovisionamiento automático para montar una máquina virtual Ubuntu en la nube (pensada para [Hetzner Cloud](https://www.hetzner.com/cloud/), aunque funciona en cualquier VPS con Ubuntu 26.04 LTS), accesible desde cualquier sitio sin depender del hardware local.

Incluye:

- 🖥️ Escritorio remoto **XFCE + XRDP**, accesible desde Windows App (Mac), Microsoft Remote Desktop o cualquier cliente RDP.
- 🛠️ Herramientas de desarrollo y depuración en C/C++: `gcc`, `gdb`, `valgrind`, `strace`, `htop`, páginas de manual completas, etc.
- 🌐 Dominio propio con **HTTPS automático** (Nginx + Let's Encrypt).
- 📁 **File Browser Quantum**, para subir/bajar archivos desde el navegador sin necesidad de SSH ni RDP.

## Motivación

En vez de depender de una VM local (VirtualBox, UTM, Parallels...), este proyecto monta un entorno de desarrollo Linux completo en un servidor en la nube:

- Accesible desde cualquier dispositivo y lugar, sin depender de tu portátil.
- Con snapshots antes de operaciones "arriesgadas" (particionado, kernel...).
- Con un coste mensual bajo (un servidor pequeño de Hetzner ronda los 4-5 €/mes).

## Requisitos previos

Antes de ejecutar el script necesitas:

1. **Un servidor Ubuntu 26.04 LTS (Live Server, amd64)** ya creado (por ejemplo, en Hetzner Cloud), con acceso `root` por SSH.
2. **Un dominio propio** (o subdominio) con un registro DNS tipo **A** apuntando a la IP pública del servidor.
    - Si usas Cloudflare, el registro debe estar en modo **"DNS only"** (nube gris), no en modo proxy — RDP y SSH no son tráfico HTTP y el proxy de Cloudflare no los soporta.
3. **Firewall del proveedor** con estos puertos de entrada abiertos:

    | Puerto | Protocolo | Para qué                                              |
    | ------ | --------- | ----------------------------------------------------- |
    | 22     | TCP       | SSH                                                   |
    | 3389   | TCP       | RDP                                                   |
    | 80     | TCP       | HTTP (validación Let's Encrypt + redirección a HTTPS) |
    | 443    | TCP       | HTTPS (File Browser)                                  |

    No hace falta abrir nada más (ni DNS/53, ni NTP/123 — el tráfico saliente ya está permitido por defecto y no estás sirviendo esos servicios).

## Uso

1. Conéctate al servidor recién creado:

    ```bash
    ssh root@TU_IP_PUBLICA
    ```

2. Descarga el script (o sube `setup_vm.sh` por `scp`):

    ```bash
    curl -O https://raw.githubusercontent.com/TU_USUARIO/TU_REPO/main/setup_vm.sh
    ```

3. Edita las variables de configuración al principio del script:

    ```bash
    nano setup_vm.sh
    ```

    | Variable            | Descripción                                                                                                                                 |
    | ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
    | `NEW_USER`          | Usuario de trabajo que se creará (no root)                                                                                                  |
    | `NEW_USER_PASSWORD` | Contraseña del usuario. Si la dejas vacía, el script te la pedirá de forma interactiva (recomendado, para no dejarla escrita en el fichero) |
    | `DOMAIN`            | Dominio que ya apunta a la IP de este servidor                                                                                              |
    | `LETSENCRYPT_EMAIL` | Email de contacto para el certificado HTTPS                                                                                                 |
    | `FILEBROWSER_PORT`  | Puerto interno de File Browser Quantum (por defecto `8080`)                                                                                 |

4. Ejecuta el script como root:

    ```bash
    sudo bash setup_vm.sh
    ```

5. Al terminar, verás un resumen con los datos de acceso.

## Qué hace el script exactamente

1. Actualiza el sistema (`apt update && apt upgrade`).
2. Crea el usuario de trabajo y lo añade al grupo `sudo`.
3. Instala **XFCE** y **XRDP**, y configura la sesión por defecto.
4. Instala herramientas de desarrollo:
    - Compilación y depuración: `build-essential`, `gdb`, `valgrind`, `manpages-dev`
    - Trazado de syscalls: `strace`, `ltrace`
    - Monitorización: `htop`, `sysstat`, `iotop`, `procps`
    - Administración: `cron`, `rsyslog`, `acl`
    - Editores y utilidades: `vim`, `nano`, `net-tools`, `lsof`, `tree`
5. Configura `~/Desktop` como directorio de trabajo por defecto al abrir terminal o conectar por SSH.
6. Instala **Nginx** y **Certbot**, y obtiene un certificado HTTPS con Let's Encrypt para el dominio indicado.
7. Instala **[File Browser Quantum](https://filebrowserquantum.com/)** (el fork activo y mantenido de File Browser, ya que el proyecto original fue archivado en agosto de 2026 sin más parches de seguridad), sirviendo todo el home del usuario, detrás del proxy de Nginx.

## Después de ejecutar el script

- **Cambia la contraseña por defecto de File Browser Quantum.** El primer arranque crea un usuario `admin` con contraseña `admin`. Entra en `https://TU_DOMINIO`, cámbiala inmediatamente en _Settings → Profile Settings_, y crea tu propio usuario desde _Settings → User Management_.
- Verifica el acceso:
    - SSH: `ssh usuario@tu_dominio`
    - RDP: conecta a `tu_dominio` con un cliente RDP (usuario y contraseña del sistema)
    - Web: `https://tu_dominio`

## Notas y recomendaciones

- **El certificado HTTPS se renueva solo.** Certbot instala un timer de systemd que comprueba dos veces al día si el certificado está cerca de caducar. Puedes verificarlo con:

    ```bash
    systemctl list-timers | grep certbot
    sudo certbot renew --dry-run
    ```

- **Idempotencia parcial.** El script se puede volver a ejecutar si algo falla a mitad de camino (por ejemplo, si Certbot falla porque el DNS aún no había propagado). No borra ni resetea lo ya instalado, pero tampoco está pensado para ejecutarse repetidamente como forma normal de uso.

- **Snapshots.** Antes de hacer prácticas que toquen particiones, el kernel, o cualquier cosa "arriesgada", se recomienda hacer un snapshot desde el panel de tu proveedor (en Hetzner: _Snapshots_ en el menú del servidor).

- **Seguridad del acceso.** Este setup prioriza la comodidad (acceder desde cualquier sitio sin VPN) sobre el máximo hardening, pensado para una VM de uso académico sin datos sensibles. Si quieres reforzarlo:
    - Restringe el firewall a tu IP en vez de "Any" cuando no necesites acceso itinerante.
    - Considera una VPN (WireGuard) en vez de exponer RDP/SSH directamente a internet.

## Licencia

Uso libre para fines educativos. Sin garantías. Revisa y adapta el script a tu proveedor y necesidades antes de ejecutarlo en producción.

<p align="center">Hecho con ❤️ por <a href="https://souhaibem.eu">Souhaib EM</a> con la ayuda de <a href="https://claude.ai">Claude AI</a>.</p>
