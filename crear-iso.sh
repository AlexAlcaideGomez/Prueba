#!/usr/bin/env bash
# Genera una ISO de instalación de "Ventana Linux": el instalador oficial de
# Debian 13 (netinst) con respuestas automáticas (preseed) que borra el disco,
# instala Debian y aplica ventana/postinstall.sh (escritorio tipo Windows).
#
# Uso: ./crear-iso.sh --usuario ana [opciones]     (ver --ayuda)
set -Eeuo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
URL_DEBIAN="https://cdimage.debian.org/debian-cd/current/amd64/iso-cd"
CACHE="$RAIZ/cache"

usuario=""
nombre=""
equipo="ventana-pc"
idioma="es_ES.UTF-8"
teclado="es"
zona="Europe/Madrid"
disco=""
desatendido=0
iso_base=""
wifi_ssid=""
wifi_clave=""
salida=""

ayuda() {
  cat <<EOF
Uso: $0 --usuario NOMBRE [opciones]

Crea una ISO que, al arrancar, FORMATEA el disco e instala Ventana Linux
(Debian 13 optimizado con escritorio XFCE de aspecto Windows).

Opciones:
  -u, --usuario NOMBRE   Usuario que se creará (obligatorio, p. ej. "ana").
  -n, --nombre TEXTO     Nombre completo del usuario (por defecto, el usuario).
      --equipo NOMBRE    Nombre del equipo en la red (por defecto: $equipo).
      --idioma LOCALE    Idioma del sistema (por defecto: $idioma).
      --teclado MAPA     Distribución de teclado (por defecto: $teclado).
      --zona ZONA        Zona horaria (por defecto: $zona).
      --disco DISPOSITIVO
                         Disco que se borrará, p. ej. /dev/sda o /dev/nvme0n1.
                         Si no se indica, el instalador preguntará cuál.
      --desatendido      No pedir confirmación antes de borrar el disco.
                         Requiere --disco. ¡Cuidado: arrancar con esa ISO
                         borra el disco tras pulsar Intro en el menú!
      --wifi-ssid RED    Red Wi-Fi para la instalación (si no hay cable).
      --wifi-clave CLAVE Contraseña WPA de esa red.
      --iso RUTA         Usar una ISO netinst de Debian 13 ya descargada.
  -o, --salida RUTA      Ruta de la ISO generada.
  -h, --ayuda            Muestra esta ayuda.

La contraseña del usuario se pide de forma interactiva, o se toma de la
variable de entorno VENTANA_CLAVE.
EOF
}

error() { printf 'Error: %s\n' "$*" >&2; exit 1; }
log()   { printf '==> %s\n' "$*"; }

while (($#)); do
  case $1 in
    -u|--usuario)  usuario=${2:?}; shift ;;
    -n|--nombre)   nombre=${2:?}; shift ;;
    --equipo)      equipo=${2:?}; shift ;;
    --idioma)      idioma=${2:?}; shift ;;
    --teclado)     teclado=${2:?}; shift ;;
    --zona)        zona=${2:?}; shift ;;
    --disco)       disco=${2:?}; shift ;;
    --desatendido) desatendido=1 ;;
    --wifi-ssid)   wifi_ssid=${2:?}; shift ;;
    --wifi-clave)  wifi_clave=${2:?}; shift ;;
    --iso)         iso_base=${2:?}; shift ;;
    -o|--salida)   salida=${2:?}; shift ;;
    -h|--ayuda)    ayuda; exit 0 ;;
    *)             ayuda >&2; error "opción desconocida: $1" ;;
  esac
  shift
done

# --- Validación ---------------------------------------------------------------

[[ -n $usuario ]] || { ayuda >&2; error "falta --usuario"; }
[[ $usuario =~ ^[a-z][a-z0-9_-]{0,31}$ ]] ||
  error "usuario no válido: usa minúsculas, números, '-' o '_' y empieza por una letra"
case $usuario in
  root|admin|daemon|bin|sys|sync|games|man|lp|mail|news|uucp|proxy|www-data|backup|list|irc|nobody|systemd-*)
    error "el nombre de usuario '$usuario' está reservado por el sistema" ;;
esac
[[ $equipo =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] || error "nombre de equipo no válido: $equipo"
[[ -n $disco && ! $disco =~ ^/dev/[a-zA-Z0-9/_-]+$ ]] && error "disco no válido: $disco"
((desatendido)) && [[ -z $disco ]] && error "--desatendido necesita --disco (p. ej. --disco /dev/sda)"
[[ -n $wifi_ssid && -z $wifi_clave ]] && error "--wifi-ssid necesita --wifi-clave"
nombre=${nombre:-$usuario}
for valor in "$nombre" "$equipo" "$idioma" "$teclado" "$zona" "$wifi_ssid" "$wifi_clave"; do
  [[ $valor != *$'\n'* ]] || error "los valores no pueden contener saltos de línea"
done

for programa in xorriso openssl sha512sum; do
  command -v "$programa" >/dev/null ||
    error "falta '$programa'. En Debian/Ubuntu: sudo apt install xorriso openssl coreutils"
done
command -v curl >/dev/null || error "falta 'curl'. En Debian/Ubuntu: sudo apt install curl"

if [[ -n ${VENTANA_CLAVE:-} ]]; then
  clave=$VENTANA_CLAVE
else
  read -rsp "Contraseña para '$usuario': " clave; echo
  read -rsp "Repite la contraseña: " clave2; echo
  [[ $clave == "$clave2" ]] || error "las contraseñas no coinciden"
fi
((${#clave} >= 6)) || error "la contraseña debe tener al menos 6 caracteres"
hash_clave=$(openssl passwd -6 -stdin <<<"$clave")
unset clave clave2

# --- ISO base de Debian -------------------------------------------------------

if [[ -z $iso_base ]]; then
  mkdir -p "$CACHE"
  log "consultando la última versión de Debian estable"
  curl -fsSL "$URL_DEBIAN/SHA512SUMS" -o "$CACHE/SHA512SUMS"
  linea=$(grep -E ' debian-[0-9.]+-amd64-netinst\.iso$' "$CACHE/SHA512SUMS" | head -n1)
  [[ -n $linea ]] || error "no se encontró la ISO netinst en $URL_DEBIAN/SHA512SUMS"
  nombre_iso=${linea##* }
  iso_base="$CACHE/$nombre_iso"
  if [[ -f $iso_base ]] && (cd "$CACHE" && sha512sum --quiet -c - <<<"$linea") 2>/dev/null; then
    log "usando $nombre_iso ya descargada"
  else
    log "descargando $nombre_iso"
    curl -fL --retry 3 -C - "$URL_DEBIAN/$nombre_iso" -o "$iso_base"
    log "verificando la suma SHA-512"
    (cd "$CACHE" && sha512sum --quiet -c - <<<"$linea") || error "la ISO descargada está corrupta; bórrala y vuelve a intentarlo"
  fi
fi
[[ -f $iso_base ]] || error "no existe la ISO: $iso_base"

contenido=$(xorriso -indev "$iso_base" -find / -type f 2>/dev/null) ||
  error "xorriso no pudo leer $iso_base"
tiene() { grep -qF "$1" <<<"$contenido"; }
for ruta in /install.amd/vmlinuz /install.amd/initrd.gz /boot/grub/grub.cfg; do
  tiene "$ruta" || error "$iso_base no parece una ISO netinst de Debian para amd64 (falta $ruta)"
done

if [[ -z $salida ]]; then
  version=$(basename "$iso_base" | sed -nE 's/^debian-([0-9.]+)-.*/\1/p')
  salida="$RAIZ/ventana-linux-${version:-debian}-amd64.iso"
fi

# --- Archivos que se añaden a la ISO -----------------------------------------

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

opciones_arranque="auto=true priority=critical preseed/file=/cdrom/preseed.cfg locale=$idioma keymap=$teclado"
opciones_kernel="--- quiet"

{
  cat <<EOF
# Respuestas automáticas para el instalador de Debian, generadas por crear-iso.sh.
# Documentación: https://www.debian.org/releases/stable/amd64/apb.es.html

### Idioma, teclado y hora
d-i debian-installer/locale string $idioma
d-i keyboard-configuration/xkb-keymap select $teclado
d-i console-setup/ask_detect boolean false
d-i time/zone string $zona
d-i clock-setup/utc boolean true
d-i clock-setup/ntp boolean true

### Red
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string $equipo
d-i netcfg/hostname string $equipo
d-i netcfg/get_domain string
d-i hw-detect/load_firmware boolean true
EOF
  if [[ -n $wifi_ssid ]]; then
    cat <<EOF
d-i netcfg/wireless_essid string $wifi_ssid
d-i netcfg/wireless_security_type select wpa
d-i netcfg/wireless_wpa string $wifi_clave
EOF
  fi
  cat <<EOF

### Réplica de paquetes
d-i mirror/country string manual
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string
d-i apt-setup/non-free-firmware boolean true
d-i apt-setup/contrib boolean false
d-i apt-setup/non-free boolean false
d-i apt-setup/services-select multiselect security, updates
d-i apt-setup/cdrom/set-first boolean false
d-i apt-setup/disable-cdrom-entries boolean true

### Usuario (sin cuenta root: el usuario administra con sudo)
d-i passwd/root-login boolean false
d-i passwd/make-user boolean true
d-i passwd/user-fullname string $nombre
d-i passwd/username string $usuario
d-i passwd/user-password-crypted password $hash_clave

### Particionado: usa el disco ENTERO (se borra todo lo que contenga)
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman/default_filesystem string ext4
d-i partman/mount_style select uuid
d-i partman-efi/non_efi_system boolean true
d-i partman-partitioning/choose_label select gpt
d-i partman-partitioning/default_label string gpt
EOF
  if [[ -n $disco ]]; then
    echo "d-i partman-auto/disk string $disco"
    echo "d-i grub-installer/bootdev string $disco"
  else
    echo "d-i grub-installer/bootdev string default"
  fi
  if ((desatendido)); then
    cat <<EOF
# Modo desatendido: no se pide confirmación antes de borrar el disco.
d-i partman-lvm/device_remove_lvm boolean true
d-i partman-md/device_remove_md boolean true
d-i partman-lvm/confirm boolean true
d-i partman-lvm/confirm_nooverwrite boolean true
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true
EOF
  else
    echo "# Sin 'partman/confirm': el instalador muestra los cambios y pide confirmación antes de borrar."
  fi
  cat <<EOF

### Paquetes: sistema base mínimo; el escritorio lo instala postinstall.sh
d-i base-installer/kernel/image string linux-image-amd64
tasksel tasksel/first multiselect
d-i pkgsel/include string xorg lightdm lightdm-gtk-greeter xfce4 network-manager sudo
d-i pkgsel/upgrade select full-upgrade
popularity-contest popularity-contest/participate boolean false

### Cargador de arranque
d-i grub-installer/only_debian boolean true
d-i grub-installer/with_other_os boolean false

### Personalización de Ventana Linux
d-i preseed/late_command string \\
    cp -r /cdrom/ventana /target/opt/ventana; \\
    in-target sh -c 'bash /opt/ventana/postinstall.sh --instalador > /var/log/ventana-postinstall.log 2>&1'

### Fin: reiniciar automáticamente
d-i finish-install/reboot_in_progress note
d-i cdrom-detect/eject boolean true
EOF
} > "$TMP/preseed.cfg"

# Menú de arranque UEFI (GRUB). En modo desatendido espera a que se pulse Intro
# para que arrancar la ISO por descuido no borre el disco.
espera_grub=10
((desatendido)) && espera_grub=-1
cat > "$TMP/grub.cfg" <<EOF
set default=0
set timeout=$espera_grub

menuentry 'Instalar Ventana Linux (BORRA EL DISCO)' {
    linux /install.amd/vmlinuz $opciones_arranque $opciones_kernel
    initrd /install.amd/initrd.gz
}
menuentry 'Instalador de Debian normal (manual)' {
    linux /install.amd/vmlinuz $opciones_kernel
    initrd /install.amd/initrd.gz
}
menuentry 'Reiniciar' {
    reboot
}
EOF

# Menú de arranque BIOS (isolinux), si la ISO lo trae. timeout en décimas; 0 = esperar.
espera_bios=100
((desatendido)) && espera_bios=0
cat > "$TMP/isolinux.cfg" <<EOF
say
say  Ventana Linux - pulsa Intro para instalar (BORRA EL DISCO).
say  Escribe "manual" e Intro para el instalador normal de Debian.
say
default ventana
prompt 1
timeout $espera_bios

label ventana
  kernel /install.amd/vmlinuz
  append initrd=/install.amd/initrd.gz $opciones_arranque $opciones_kernel

label manual
  kernel /install.amd/vmlinuz
  append initrd=/install.amd/initrd.gz $opciones_kernel
EOF

# --- Construcción -------------------------------------------------------------

mapeos=(
  -map "$TMP/preseed.cfg" /preseed.cfg
  -map "$RAIZ/ventana" /ventana
  -map "$TMP/grub.cfg" /boot/grub/grub.cfg
)
tiene /isolinux/isolinux.cfg && mapeos+=(-map "$TMP/isolinux.cfg" /isolinux/isolinux.cfg)

log "generando $salida"
rm -f "$salida"
xorriso -indev "$iso_base" -outdev "$salida" \
  "${mapeos[@]}" \
  -boot_image any replay \
  >/dev/null 2>"$TMP/xorriso.log" || { cat "$TMP/xorriso.log" >&2; error "xorriso no pudo crear la ISO"; }

log "ISO lista: $salida"
cat <<EOF

Siguientes pasos:
  1. Pruébala primero en una máquina virtual (ver README.md).
  2. Grábala en un USB, por ejemplo:  sudo dd if="$salida" of=/dev/sdX bs=4M status=progress oflag=sync
  3. Arranca el ordenador desde el USB. Al instalar se BORRARÁ el disco elegido.

La ISO contiene el hash de tu contraseña: no la compartas.
EOF
