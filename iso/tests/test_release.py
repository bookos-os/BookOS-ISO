"""Ejecuta el flujo de solo ISO con compiladores y privilegios simulados."""
import os
import contextlib
import io
import pty
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'release.sh'


class PruebasConstruccionLocal(unittest.TestCase):
    def setUp(self):
        self.temporal = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporal.cleanup)
        self.raiz = Path(self.temporal.name)
        self.iso = self.raiz / 'BookOS-ISO/iso'
        self.iso.mkdir(parents=True)
        shutil.copy2(SCRIPT, self.iso / 'release.sh')
        self.bin = self.raiz / 'bin'
        self.bin.mkdir()
        self.registro = self.raiz / 'registro'
        self.entorno = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ['PATH'],
                            BOOKOS_BUILD_ROOT=str(self.raiz / 'trabajo'), REGISTRO=str(self.registro))
        self.entorno.pop('OUTDIR', None)
        for nombre in ('podman', 'rpm', 'rpmkeys', 'rpmsign', 'createrepo_c', 'gpg', 'rsync'):
            self.programa(self.bin / nombre, 'exit 0\n')
        self.programa(self.bin / 'id', 'case "$1" in -u|-g) echo 1000;; *) /usr/bin/id "$@";; esac\n')
        # Solo se simula el espacio: las operaciones de copiar manifiestos,
        # verificar checksum y la secuencia de fases siguen siendo reales.
        self.programa(self.bin / 'python3',
                      f'if [ "$1" = - ]; then cat >/dev/null; exit 0; fi\nexec "{sys.executable}" "$@"\n')
        self.programa(self.bin / 'sudo', 'echo sudo >> "$REGISTRO.sudo"\nexec "$@"\n')
        self.programa(self.bin / 'chown', 'echo permisos >> "$REGISTRO"\n')
        (self.iso / 'app-catalog.py').write_text(
            'import os,sys\nfrom pathlib import Path\n'
            'with Path(os.environ["REGISTRO"]).open("a") as f:f.write(sys.argv[1]+"\\n")\n')
        self.programa(self.iso / 'build-apps-in-podman.sh', '''
echo apps >> "$REGISTRO"
mkdir -p "$BOOKOS_BUILD_ROOT/package-check/repo"
echo '[]' > "$BOOKOS_BUILD_ROOT/package-check/repo/bookos-apps.json"
echo '{}' > "$BOOKOS_BUILD_ROOT/package-check/repo/bookos-fuentes.json"
''')
        self.programa(self.iso / 'check-packages-in-podman.sh', '''
echo sistema >> "$REGISTRO"
[ "${FALLAR_PAQUETES:-0}" = 0 ]
''')
        self.programa(self.iso / 'check-artifacts.sh', 'echo verificar-firmas >> "$REGISTRO"\n')
        self.programa(self.iso / 'build-in-podman.sh', '''
echo "iso $* $EDITION $SIGN" >> "$REGISTRO"
mkdir -p "$OUTDIR"
cd "$OUTDIR"
nombre="bookos-$2-$1-x86_64.iso"
echo 'imagen simulada' > "$nombre"
sha256sum "$nombre" > "$nombre.sha256"
''')
        firma = self.raiz / 'Bookos-web/deploy/sign-and-publish.sh'
        firma.parent.mkdir(parents=True)
        self.programa(firma, '[ "$1" = --solo-firmar ]\necho firmar >> "$REGISTRO"\n')
        for nombre in ('qemu-system-x86_64', 'curl', 'ssh'):
            self.programa(self.bin / nombre, f'echo PROHIBIDO-{nombre} >> "$REGISTRO"\nexit 97\n')

    @staticmethod
    def programa(path, texto):
        path.write_text('#!/usr/bin/bash\nset -euo pipefail\n' + texto)
        path.chmod(0o755)

    def ejecutar(self, *opciones):
        return subprocess.run(['bash', str(self.iso / 'release.sh'), 'dev', '0.7.1', *opciones],
                              env=self.entorno, capture_output=True, text=True)

    def test_solo_iso_recompila_firma_y_termina_sin_publicar(self):
        resultado = self.ejecutar('--solo-iso')
        self.assertEqual(resultado.returncode, 0, resultado.stdout + resultado.stderr)
        self.assertEqual(self.registro.read_text().splitlines(),
                         ['comprobar', 'apps', 'sistema', 'firmar', 'resign',
                          'verificar-firmas', 'iso dev 0.7.1 completa 0', 'permisos'])
        self.assertEqual(Path(str(self.registro) + '.sudo').read_text().splitlines(), ['sudo'])
        salida = self.raiz / 'trabajo/release/0.7.1'
        self.assertTrue((salida / 'bookos-0.7.1-dev-x86_64.iso.sha256').is_file())
        self.assertTrue((salida / 'bookos-apps.json').is_file())
        self.assertTrue((salida / 'bookos-fuentes.json').is_file())

    def test_un_fallo_de_paquetes_impide_firmar_y_componer(self):
        self.entorno['FALLAR_PAQUETES'] = '1'
        resultado = self.ejecutar('--solo-iso')
        self.assertNotEqual(resultado.returncode, 0)
        self.assertEqual(self.registro.read_text().splitlines(), ['comprobar', 'apps', 'sistema'])

    def test_comprobar_no_compila_ni_firma(self):
        resultado = self.ejecutar('--solo-iso', '--comprobar')
        self.assertEqual(resultado.returncode, 0, resultado.stderr)
        self.assertEqual(self.registro.read_text().splitlines(), ['comprobar'])

    def test_rechaza_reanudar_solo_iso_en_una_fase_de_publicacion(self):
        resultado = self.ejecutar('--solo-iso', '--desde', '6')
        self.assertNotEqual(resultado.returncode, 0)
        self.assertFalse(self.registro.exists())

    def test_no_sobrescribe_una_iso_anterior(self):
        salida = self.raiz / 'trabajo/release/0.7.1'
        salida.mkdir(parents=True)
        imagen = salida / 'bookos-0.7.1-dev-x86_64.iso'
        imagen.write_bytes(b'anterior')
        resultado = self.ejecutar('--solo-iso')
        self.assertNotEqual(resultado.returncode, 0)
        self.assertEqual(imagen.read_bytes(), b'anterior')
        self.assertEqual(self.registro.read_text().splitlines(), ['comprobar'])

    def test_el_espacio_estimado_avisa_sin_bloquear_podman(self):
        script = SCRIPT.read_text().split('<<\'PY\'\n', 1)[1].split('\nPY\n', 1)[0]
        espacio = shutil.disk_usage(self.raiz)._replace(free=10 * 1024**3)
        avisos = io.StringIO()
        argumentos = ['-', str(self.raiz), str(self.raiz), '1']
        with patch.object(sys, 'argv', argumentos), patch('shutil.disk_usage', return_value=espacio):
            with contextlib.redirect_stderr(avisos):
                exec(compile(script, str(SCRIPT), 'exec'), {})
        self.assertIn('Aviso:', avisos.getvalue())
        self.assertIn('se continúa', avisos.getvalue())

    def test_desbloquea_la_clave_en_la_terminal_antes_de_firmar_el_lote(self):
        self.programa(self.bin / 'gpg', '''
if [ "$1" = --pinentry-mode ]; then
    [ "$2" = loopback ]
    [ "$GPG_TTY" = "$(tty)" ]
    echo desbloquear >> "$REGISTRO"
    [ "${FALLAR_DESBLOQUEO:-0}" = 0 ]
fi
''')
        for fallo in ('0', '1'):
            with self.subTest(fallo=fallo):
                self.entorno['FALLAR_DESBLOQUEO'] = fallo
                self.entorno['GPG_TTY'] = 'no es un tty'
                self.registro.unlink(missing_ok=True)
                self.entorno['OUTDIR'] = str(self.raiz / ('salida-' + fallo))
                maestro, esclavo = pty.openpty()
                try:
                    resultado = subprocess.run(
                        ['bash', str(self.iso / 'release.sh'), 'dev', '0.7.1', '--solo-iso'],
                        env=self.entorno, stdin=esclavo, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                finally:
                    os.close(esclavo)
                    os.close(maestro)
                pasos = self.registro.read_text().splitlines()
                self.assertIn('desbloquear', pasos)
                if fallo == '0':
                    self.assertEqual(resultado.returncode, 0, resultado.stdout + resultado.stderr)
                    self.assertLess(pasos.index('desbloquear'), pasos.index('firmar'))
                else:
                    self.assertNotEqual(resultado.returncode, 0)
                    self.assertNotIn('firmar', pasos)
