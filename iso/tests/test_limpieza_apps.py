"""La limpieza debe conservar el RPM antes de borrar los targets de Cargo."""
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest

ISO = Path(__file__).resolve().parents[1]


class PruebasLimpiezaApps(unittest.TestCase):
    def test_limpia_despues_de_guardar_el_rpm_y_con_el_target_correcto(self):
        texto = (ISO / 'build-apps-fedora.sh').read_text()
        final = texto[texto.index('    for anterior in /work/repo/*.rpm;'):]
        final = final.split('\ndone\npython3 ', 1)[0]
        for tecnologia, app, paquete, cantidad in (
            ('tauri', 'camera', 'bookos-camera', 1),
            ('tauri', 'remap', 'bookos-teclas', 2),
            ('gpui', 'explorer', 'bookos-explorer', 1),
            ('firefox', 'bookos-browser', 'bookos-browser', 0),
        ):
            with self.subTest(app=app), tempfile.TemporaryDirectory() as temporal:
                raiz = Path(temporal)
                fuente = raiz / 'sources' / app
                fuente.mkdir(parents=True)
                (raiz / 'repo').mkdir()
                target = raiz / 'target'
                target.mkdir()
                artefacto = target / 'app.rpm'
                artefacto.write_bytes(b'RPM de prueba')
                daemon = fuente / 'teclasd/target'
                daemon.mkdir(parents=True)
                (daemon / 'binario').touch()
                nombre = paquete + '-1-1.x86_64'
                guion = f'''
set -euo pipefail
tecnologia={tecnologia}
app={app}
paquete={paquete}
temporal="{raiz}/empaquetado"
export CARGO_TARGET_DIR="{target}"
artefactos=("{artefacto}")
cd "{fuente}"
rpm() {{ printf '%s' '{nombre}'; }}
cargo() {{
    [ "$1" = clean ]
    [ -s "{raiz}/repo/{nombre}.rpm" ]
    printf '%s\\n' "$CARGO_TARGET_DIR" >> "{raiz}/limpiezas"
    rm -rf -- "$CARGO_TARGET_DIR"
}}
'''
                resultado = subprocess.run(['bash'], input=guion + final.replace('/work/', str(raiz) + '/'),
                                           capture_output=True, text=True)
                self.assertEqual(resultado.returncode, 0, resultado.stdout + resultado.stderr)
                self.assertEqual((raiz / 'repo' / (nombre + '.rpm')).read_bytes(), b'RPM de prueba')
                limpiezas = raiz / 'limpiezas'
                llamadas = limpiezas.read_text().splitlines() if limpiezas.exists() else []
                self.assertEqual(len(llamadas), cantidad)
                if cantidad:
                    self.assertEqual(llamadas[0], str(target))
                    self.assertFalse(target.exists())
                if cantidad == 2:
                    self.assertEqual(llamadas[1], str(daemon))
                    self.assertFalse(daemon.exists())

    def test_el_escritorio_no_pasa_por_la_limpieza_de_aplicaciones(self):
        catalogo = runpy.run_path(str(ISO / 'app-catalog.py'))
        self.assertNotIn('bookos-desktop', {app[1] for app in catalogo['APPS']})
        self.assertNotIn('cargo clean', (ISO / 'check-packages.sh').read_text())
