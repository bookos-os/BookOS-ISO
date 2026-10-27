# BookOS 0.7.1 — Fedora 44 y escritorio propio

La imagen completa inicia el escritorio nativo de BookOS escrito en Rust
(compositor Smithay + shell integrado), con nuestro greeter sobre greetd y
Cage parcheado. Incluye todas las aplicaciones de `app-catalog.py`: Archivos,
Bloc de notas, Monitor del sistema, Fuentes y Audio en GPUI; las demás en
Tauri, además de Aether Browser y Bienvenida. Firefox proporciona el motor de
Aether y el instalador; no aparece como un segundo navegador en el menú.
No instala Plasma, SDDM, Dolphin ni la recuperación basada en KWin.
Se conservan el escritorio Wayland, XWayland, servicios
esenciales, firmware y soporte Samsung Galaxy Book (audio/huella y compilación
DKMS). No incluye el entorno completo de aplicaciones Fedora KDE.

## Construir la 0.7.1 para probar en un pendrive

Desde `BookOS-ISO`, sin sudo:

```bash
bash iso/release.sh dev 0.7.1 --solo-iso
```

Recompila las veinte aplicaciones y los componentes propios, reconstruye
los recursos, comprueba dependencias y conflictos, firma los RPM y compone
la edición completa. Solo la composición solicita sudo. No publica ni abre
una máquina virtual. Se necesitan conexión a Internet, Podman, Python 3,
sudo, RPM/rpmkeys/rpmsign, createrepo_c, GPG y rsync. La clave privada de
firma de BookOS debe estar importada en el llavero del usuario: se reutiliza
el proceso de firma existente, sin copiar claves al contenedor.

La comprobación previa avisa por debajo de un margen estimado de 60 GiB para
una construcción sin caché (35 GiB al reanudar), pero no bloquea por ese
umbral. Después de copiar el RPM de cada app al repo local se ejecuta
`cargo clean`, también para el daemon de Teclas. Se conservan las descargas
de Cargo y npm, pero las dependencias de Rust se recompilan para la siguiente
app. `bookos-desktop` queda excluido de esa limpieza. Podman también consume
espacio del anfitrión. Puedes comprobar los requisitos
sin compilar añadiendo `--comprobar`, o usar otro disco:

```bash
BOOKOS_BUILD_ROOT=/ruta/con/espacio/bookos-0.7.1 bash iso/release.sh dev 0.7.1 --solo-iso
```

El resultado predeterminado es `.build/release/0.7.1/bookos-0.7.1-dev-x86_64.iso`,
acompañado de su `.sha256` y los manifiestos de aplicaciones y fuentes.
Los RPM van firmados; la ISO candidata lleva checksum. La firma minisign y
la publicación pertenecen al flujo de lanzamiento completo.

Graba el archivo ISO como imagen en el dispositivo USB completo; copiarlo
como archivo dentro del pendrive no lo hace arrancable. La grabación borra
el contenido del dispositivo que elijas. Prueba primero el live y luego la
instalación en un disco de pruebas.

Si una fase falla, se detiene sin componer una imagen parcial. Con los RPM
ya construidos se puede reanudar con `--desde 2` (firma) o `--desde 3`
(composición). No sobrescribe una ISO anterior: `OUTDIR=/otra/ruta` conserva
las dos. Los proyectos hermanos se leen; las copias de compilación y los
registros quedan bajo `BOOKOS_BUILD_ROOT`.

## Ediciones

`EDITION=completa|minima|servidor` (por defecto `completa`) elige qué lleva la
imagen. La parte común está en `bookos-base.ks`; lo propio de cada una, en
`edicion-<edición>.ks`, que `profile.py` inserta antes de la `%post` común.
La completa conserva el nombre de fichero de siempre; las otras llevan la
edición detrás del canal (`bookos-0.6.2-dev-minima-x86_64.iso`).

```bash
sudo EDITION=minima bash iso/build-in-podman.sh dev 0.6.2
python3 iso/profile.py --check --edition servidor
```

- **completa**: lo de arriba, con instalador gráfico (WebUI en Firefox).
- **minima**: para 512 MB de RAM. bookos-desktop, SDDM y foot; sin apps Tauri
  (cada una pasa de 300 MB con su WebKit), sin Firefox, sin KWin ni PySide6
  (`bookos-desktop-recovery`) y sin el soporte del Galaxy Book. Instalador en
  modo texto: «Instalar en el disco duro» abre `bookos-instalar` en foot.
- **servidor**: sin escritorio. SSH y Cockpit (`https://<ip>:9090`, con el
  tema de `bookos-branding`) activos y con el puerto abierto. El live entra en
  tty1; se instala con `bookos-instalar`. En el disco instalado se retira el
  instalador, que arrastra GTK4 y Mesa (530 MiB medidos).

Resolución en fedora:44 (`dnf --assumeno`, sin RPM Fusion, con los Requires de
los spec nuevos de bookos-desktop y bookos-branding): completa 1091 paquetes y
4,1 GiB instalados; mínima 638 y 1,9 GiB; servidor 530 y 1,6 GiB en el live
(unos 1,1 GiB tras retirar el instalador).

Mínima y servidor necesitan bookos-desktop >= 0.1.0-11 y bookos-branding >=
0.6.2-5 en el repo; con los anteriores el `%post` de verificación aborta.

## Validación sin instalar el sistema

```bash
python3 -m unittest discover -s iso/tests -v
python3 iso/profile.py --check
bash -n iso/build-iso.sh iso/build-in-podman.sh iso/files/bookos-boot-finalize.sh
```

Requiere Python con el paquete Fedora `pykickstart`. El constructor usa el mismo
renderizador y valida todos los scripts del kickstart antes de ejecutar lorax.

Primero se compilan todas las apps desde los proyectos hermanos actuales, en
Fedora 44, sin reutilizar los RPM publicados ni modificar esos proyectos:

```bash
bash iso/build-apps-in-podman.sh
```

Los nombres del menú se localizan durante el empaquetado; los identificadores
y comandos permanecen estables. El manifiesto `bookos-apps.json` registra los
RPM y sus SHA-256. El modo local exige ese manifiesto y excluye esas apps del
repositorio remoto. La copia de trabajo y los logs quedan en `.build/apps/`.

Después se reconstruyen los paquetes de integración, iconos y widgets y se resuelven todas las dependencias
en un contenedor desechable (ejecutar desde BookOS-ISO):

```bash
bash iso/check-packages-in-podman.sh
```

Fuentes visuales: los proyectos hermanos en el directorio BookOS. Los RPM
candidatos quedan en `.build/package-check/repo/`; el informe de resolución,
con versiones, repositorios y tamaños, en `.build/package-check/dependency-resolution.log`.
Esta comprobación no instala la transacción ni publica archivos. Los RPM
construidos son candidatos sin firma; no deben distribuirse así.

Los cuatro packs se instalan también bajo la ruta que consulta Ajustes mediante
enlaces a los temas del sistema. Los widgets se recogen de sus proyectos, sin
capturar el escritorio del desarrollador, y sus traducciones se compilan con
el identificador usado en la ISO. Véase la [documentación de traducciones de Plasma](https://develop.kde.org/docs/plasma/widget/translations-i18n/).

## Construir la ISO candidata

```bash
sudo bash iso/build-in-podman.sh dev 0.6.2 N
```

Por defecto usa `.build/package-check/repo` como repo local (`LOCALREPO=…`
para otro). Necesita sudo real y acceso a dispositivos loop. Resultado:
`bookos-0.6.2-dev-x86_64.iso` y su SHA-256. El trabajo temporal queda
en `.build/compose/`. Cambiar la versión o directorio de salida para cada
construcción: no se reutilizan imágenes con firmas antiguas.

El último `%post` restaura los contextos SELinux completos con `setfiles -F`
y verifica ejecutables esenciales. Es necesario al construir en contenedores:
la 0.6.2 original conservaba el rol de proceso `unconfined_r` en archivos,
lo que bloqueaba udev, D-Bus y SDDM al arrancar en modo enforcing. Corregir solo
el tipo de la etiqueta no basta. El contenedor también necesita
`policycoreutils` para la llamada de Anaconda a `load_policy` al terminar.

Cada construcción guarda sus registros en `.build/compose/logs/compose-*`.
`check-compose-logs.sh` impide entregar una ISO si faltan los registros o
contienen errores de Anaconda o dracut, aunque lorax haya devuelto éxito.

El sistema se llama «BookOS» a secas en todas partes (menú del USB, etiqueta
del volumen, instalador, entrada UEFI y `PRETTY_NAME`); la versión solo va en
el nombre del fichero y en `VERSION`/Ajustes.

El modo servidor se selecciona con `NO_LOCAL_REPO=1`, pero primero deben estar
publicados los nuevos RPM: branding >= 0.6.2-1, welcome >= 1.0.0-4 e
integración >= 0.6.1-8, además de meta 0.6.1-3 y keyring 0.6.1-5. El
`%post` de verificación del kickstart aborta con versiones anteriores. No hay
que borrar estas comprobaciones para usar un repo antiguo.

La edición completa incluye todo el catálogo sin necesitar `ALLAPPS=S`.
`APPS="..."` permite añadir otros paquetes al invocar `build-iso.sh` directamente.

## Firmas y actualizaciones

Los RPM se verifican con GPG; minisign corresponde a la ISO. La clave GPG
pública viaja en bookos-keyring y se importa durante la composición, fuera de
la transacción RPM. El sistema instalado verifica también los RPM locales.
No se desactiva la comprobación de firmas para evitar un error.

```bash
bash iso/check-artifacts.sh rpm ruta/paquete-firmado.rpm
MINISIGN_PUBKEY=/ruta/clave-publica \\
  bash iso/check-artifacts.sh iso ruta/imagen.iso
```

El verificador distingue una firma válida de un RPM que solo tiene digests.
Usa una base RPM temporal, sin modificar el llavero del equipo. El publicador
comprueba la firma de la ISO antes de subirla. `SIGN=1` exige herramienta y
claves; `SIGN=auto` permite una candidata local sin firma si no hay clave.
Para firmar dentro del constructor directo se admiten `MINISIGN_SECRET_KEY`
y `MINISIGN_PUBKEY`; el wrapper de Podman no monta claves privadas.

## Comprobar arranque y escritorio antes de publicar

1. VirtualBox: disco virtual nuevo de 40 GiB, 4 GiB RAM, 2 CPU, VMSVGA y 3D
   desactivado. Probar el live una vez con BIOS y otra con EFI, con discos
   separados. Registrar versión de VirtualBox, checksum, mensaje y VBox.log.
2. Instalar en cada VM, retirar la ISO y arrancar desde disco. Comprobar menú
   BookOS y acceso al escritorio. En otra VM de prueba, comprobar convivencia
   con un Linux existente y cuál de sus cargadores está activo.
3. En el destino, revisar `/var/log/bookos-boot-finalize.log` y
   `/var/log/bookos-anaconda-boot.log`, ESP vfat, UUID de /boot, BLS,
   kernel e initramfs. La instalación aborta si falla un paso esencial.
4. Comprobar Wi-Fi/Bluetooth/audio y huella en Samsung real; una VM no verifica
   esos controladores. Comprobar también bloqueo, suspensión, USB, Shell desde
   Dolphin, apertura de texto e imágenes y las aplicaciones seleccionadas.
5. Instalar y actualizar un RPM BookOS firmado desde Tienda y desde archivo;
   comprobar rechazo de un RPM sin firma o alterado. Actualizar kernel y
   reiniciar, conservando el kernel anterior (`installonly_limit=2`).

El inventario final queda dentro del sistema en `/usr/share/bookos/packages.tsv`
(nombre, versión/arquitectura, bytes instalados y repositorio de origen).
No se renombra el subvolumen Btrfs de Anaconda. La finalización conserva una
ruta EFI de reserva existente y no reescribe el ESP en el primer arranque.

El rendimiento de BookOS Shell queda fuera de esta modificación. Las pruebas
de sintaxis y resolución no sustituyen una instalación y arranque reales.
