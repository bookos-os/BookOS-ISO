# BookOS 0.7.0: escritorio propio y paquetes firmados

## Novedades

- **Escritorio BookOS de serie.** El panel, el dock, el launchpad, la pantalla de bloqueo y los gestos del touchpad los dibuja ahora el escritorio de BookOS. Plasma ya no viene incluido, así que el sistema es más ligero y arranca sin pantalla de carga.
- **Actualizaciones sin preguntas.** Todos los paquetes van firmados, y la clave de BookOS viene dentro de la ISO. `dnf` comprueba cada paquete en silencio y solo avisa si algo no cuadra.
- **ISO firmada.** Cada imagen incluye su firma minisign, para que puedas comprobar que es la oficial.

## Cambios

- Fuera los widgets, el tema global y la disposición del panel de Plasma, porque los sustituye el escritorio nuevo.
- BookOS Ajustes activa y desactiva el repositorio de BookOS sin descargar configuración del servidor.
- El número de serie del equipo ya no es legible por cualquier usuario.

## Conocido

- Los equipos que actualicen desde 0.6.x conservan en su carpeta personal la configuración vieja de Plasma. No afecta al escritorio nuevo.
