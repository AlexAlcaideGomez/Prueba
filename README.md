# Ventana Linux

Crea un USB de instalación que **formatea el ordenador** e instala un Linux
ligero y optimizado (Debian 13 «trixie») con un escritorio **parecido a
Windows**: barra de tareas abajo, menú Inicio, bandeja del sistema con el
reloj a la derecha y botones de ventana a la derecha.

> ⚠️ **La instalación borra por completo el disco elegido.** Haz copia de
> seguridad antes y pruébalo primero en una máquina virtual.

## Qué incluye

| | |
|---|---|
| **Base** | Debian 13 estable, con actualizaciones de seguridad automáticas |
| **Escritorio** | XFCE con barra de tareas inferior estilo Windows 10, menú Whisker como menú Inicio, tema plano Arc, iconos Papirus y fuentes Noto |
| **Atajos** | Tecla Windows → menú Inicio · Win+E → archivos · Win+R → ejecutar · Win+L → bloquear · Ctrl+Mayús+Esc → administrador de tareas |
| **Aplicaciones** | Firefox, LibreOffice (Writer, Calc, Impress), VLC, visor de imágenes, editor de texto, compresor de archivos, impresoras, Synaptic para instalar programas |
| **Compatibilidad** | Fuentes con las mismas medidas que Arial, Times, Calibri y Cambria, para que los documentos de Office se vean igual |
| **Optimización** | Swap comprimida en RAM (zram + zstd), `earlyoom` para que el equipo no se congele si se queda sin memoria, TRIM semanal para SSD, diario del sistema limitado a 200 MB, GRUB con 1 s de espera y sin paquetes innecesarios (sin tareas de tasksel) |

Requisitos del equipo de destino: PC de 64 bits (x86-64) con UEFI o BIOS, 2 GB
de RAM como mínimo (4 GB recomendados), 20 GB de disco y **conexión a
Internet durante la instalación** (preferiblemente por cable). Funciona con
Secure Boot activado porque usa los cargadores firmados de Debian.

## 1. Crear la ISO

Necesitas un equipo con Linux (o WSL en Windows) con `xorriso`, `openssl` y
`curl`:

```bash
sudo apt install xorriso openssl curl
./crear-iso.sh --usuario ana --nombre "Ana López"
```

El script pide la contraseña del usuario, descarga la última ISO *netinst* de
Debian 13 (unos 750 MB, se guarda en `cache/` y se verifica su SHA-512) y
genera `ventana-linux-<versión>-amd64.iso`.

Opciones útiles (`./crear-iso.sh --ayuda` para verlas todas):

| Opción | Uso |
|---|---|
| `--equipo nombre-pc` | Nombre del equipo en la red |
| `--idioma`, `--teclado`, `--zona` | Por defecto `es_ES.UTF-8`, `es`, `Europe/Madrid`. Para México: `--idioma es_MX.UTF-8 --teclado latam --zona America/Mexico_City` |
| `--wifi-ssid RED --wifi-clave CLAVE` | Conectarse por Wi-Fi durante la instalación si no hay cable |
| `--disco /dev/nvme0n1` | Fija el disco que se borrará en lugar de preguntarlo |
| `--desatendido` | No pide confirmación antes de borrar (requiere `--disco`) |
| `--iso ruta.iso` | Usar una ISO netinst de Debian 13 ya descargada |

La ISO contiene el hash de la contraseña: no la compartas.

## 2. Grabarla en un USB

- **Linux**: `sudo dd if=ventana-linux-*.iso of=/dev/sdX bs=4M status=progress oflag=sync`
  (`/dev/sdX` es el USB; compruébalo con `lsblk`, porque `dd` borra lo que haya).
- **Windows**: [Rufus](https://rufus.ie) en modo *DD* o
  [balenaEtcher](https://etcher.balena.io).

## 3. Instalar

1. Arranca el ordenador desde el USB (tecla F12, F8, F11 o Esc al encenderlo,
   según el fabricante).
2. Elige **«Instalar Ventana Linux (BORRA EL DISCO)»**. Arranca sola a los 10 s;
   en modo `--desatendido` espera a que pulses Intro.
3. El instalador hace todo solo, salvo dos preguntas de seguridad (a menos que
   uses `--disco`/`--desatendido`):
   - qué disco borrar, si el equipo tiene más de uno;
   - la confirmación final de **«¿Escribir los cambios en los discos?»**.
4. Tarda entre 15 y 40 minutos según la conexión. Al terminar se reinicia y
   aparece la pantalla de inicio de sesión. Retira el USB.

Si algo falla durante la personalización, el registro está en
`/var/log/ventana-postinstall.log` del sistema instalado.

## Probar en una máquina virtual

Con QEMU (UEFI):

```bash
sudo apt install qemu-system-x86 ovmf
qemu-img create -f qcow2 disco-prueba.qcow2 25G
qemu-system-x86_64 -enable-kvm -m 4096 -smp 2 \
  -bios /usr/share/ovmf/OVMF.fd \
  -drive file=disco-prueba.qcow2,if=virtio \
  -cdrom ventana-linux-*.iso -boot d
```

En VirtualBox o VMware basta con crear una VM «Debian 64-bit» con 25 GB de
disco y montar la ISO.

## Aplicar el aspecto a un Debian ya instalado

`ventana/postinstall.sh` también funciona en un Debian 13 existente (por
ejemplo, uno instalado con la ISO oficial sin escritorio):

```bash
sudo ./ventana/postinstall.sh
```

No sobrescribe la configuración que ya tengan los usuarios. Para que un
usuario con XFCE ya configurado adopte el aspecto de Ventana, puede borrar
`~/.config/xfce4` antes de volver a iniciar sesión. El firmware y el
microcódigo solo se instalan si el componente `non-free-firmware` está en las
fuentes de APT.

## Estructura del proyecto

```
crear-iso.sh                  Genera la ISO (preseed + menús de arranque)
ventana/
  paquetes.txt                Lista de paquetes que se instalan
  postinstall.sh              Instala paquetes y aplica la configuración
  archivos/                   Se copia tal cual sobre / del sistema instalado
    etc/skel/.config/xfce4/   Panel tipo Windows, tema, ventanas y menú Inicio
    etc/default/zramswap      Swap comprimida en RAM
    etc/sysctl.d/             Ajustes de memoria del kernel
    usr/local/bin/ventana-primer-inicio   Atajos de teclado (primer inicio de sesión)
```

Para añadir o quitar programas, edita `ventana/paquetes.txt` y vuelve a crear
la ISO.

## Cómo funciona

`crear-iso.sh` no modifica el instalador de Debian: toma la ISO oficial y le
añade un archivo de respuestas automáticas
([preseed](https://www.debian.org/releases/stable/amd64/apb.es.html)), la
carpeta `ventana/` y un menú de arranque que lanza el instalador en modo
automático. El instalador particiona el disco (GPT, ext4 y swap), instala un
sistema base mínimo con XFCE y, al final, ejecuta `postinstall.sh` dentro del
sistema nuevo para instalar el resto de paquetes y aplicar la configuración.
