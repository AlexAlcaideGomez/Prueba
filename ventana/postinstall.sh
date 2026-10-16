#!/usr/bin/env bash
# Convierte un Debian 13 en "Ventana Linux": escritorio XFCE con aspecto de
# Windows y ajustes de rendimiento.
#
# Lo ejecuta el instalador automáticamente (con --instalador), pero también
# sirve sobre un Debian 13 ya instalado:  sudo ./postinstall.sh
set -Eeuo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODO_INSTALADOR=0
[[ ${1:-} == --instalador ]] && MODO_INSTALADOR=1

export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

log()   { printf '[ventana] %s\n' "$*"; }
aviso() { printf '[ventana] AVISO: %s\n' "$*" >&2; }
trap 'aviso "falló la línea $LINENO: $BASH_COMMAND"' ERR

if [[ $EUID -ne 0 ]]; then
  echo "Este script debe ejecutarse como root (sudo $0)." >&2
  exit 1
fi
if [[ ! -f /etc/debian_version ]]; then
  echo "Este script solo funciona en Debian." >&2
  exit 1
fi

leer_paquetes() {
  sed -e 's/#.*//' "$DIR/paquetes.txt" | tr -s '[:space:]' '\n' | sed '/^$/d'
}

existe_paquete() {
  local candidato
  candidato=$(apt-cache policy "$1" 2>/dev/null | sed -n 's/^ *Candidate: *//p')
  [[ -n $candidato && $candidato != "(none)" ]]
}

# Paquetes de traducción según el idioma del sistema (p. ej. es_ES -> es-es / es).
paquetes_idioma() {
  local loc lang tag
  # shellcheck source=/dev/null
  loc=$( (. /etc/default/locale 2>/dev/null; printf '%s' "${LANG:-}") )
  loc=${loc%%.*}
  [[ $loc == *_* ]] || return 0
  lang=${loc%%_*}
  tag="$lang-$(tr '[:upper:]' '[:lower:]' <<<"${loc#*_}")"
  local base cand
  for base in firefox-esr-l10n libreoffice-l10n; do
    for cand in "$base-$tag" "$base-$lang"; do
      if existe_paquete "$cand"; then echo "$cand"; break; fi
    done
  done
  existe_paquete "hunspell-$lang" && echo "hunspell-$lang"
  return 0
}

instalar_paquetes() {
  local -a disponibles=() faltan=()
  local p
  for p in "$@"; do
    if existe_paquete "$p"; then disponibles+=("$p"); else faltan+=("$p"); fi
  done
  if ((${#faltan[@]})); then
    aviso "no están en los repositorios y se omiten: ${faltan[*]}"
  fi
  if ((${#disponibles[@]})); then
    apt-get install "${APT_OPTS[@]}" "${disponibles[@]}"
  fi
}

# Copia la configuración de /etc/skel a los usuarios que ya existen (el
# instalador crea el usuario antes de que se ejecute este script). Nunca
# sobrescribe un archivo que el usuario ya tenga.
aplicar_skel_a_usuarios() {
  local usuario uid gid home f
  while IFS=: read -r usuario _ uid gid _ home _; do
    ((uid >= 1000 && uid < 60000)) || continue
    [[ -d $home ]] || continue
    log "aplicando el aspecto de escritorio a $usuario"
    while IFS= read -r f; do
      [[ -d $home/$f ]] || install -d -o "$uid" -g "$gid" "$home/$f"
    done < <(cd /etc/skel && find .config -type d)
    while IFS= read -r f; do
      [[ -e $home/$f ]] || install -m 0644 -o "$uid" -g "$gid" "/etc/skel/$f" "$home/$f"
    done < <(cd /etc/skel && find .config -type f)
  done < /etc/passwd
}

log "actualizando la lista de paquetes"
apt-get update

log "instalando el escritorio y las aplicaciones"
mapfile -t paquetes < <(leer_paquetes; paquetes_idioma)
instalar_paquetes "${paquetes[@]}"

log "copiando la configuración de Ventana Linux"
cp -r "$DIR/archivos/." /
chmod 0755 /usr/local/bin/ventana-primer-inicio

aplicar_skel_a_usuarios

log "activando servicios"
for servicio in lightdm.service zramswap.service earlyoom.service fstrim.timer; do
  systemctl enable "$servicio" 2>/dev/null || aviso "no se pudo activar $servicio"
done
systemctl set-default graphical.target

if ((MODO_INSTALADOR)) && [[ -f /etc/default/grub ]]; then
  # El disco entero es de Ventana Linux: no hace falta esperar en el menú de arranque.
  sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' /etc/default/grub
  update-grub || aviso "update-grub falló; se mantiene la configuración anterior de GRUB"
fi

apt-get clean
log "listo. Reinicia para entrar en el nuevo escritorio."
