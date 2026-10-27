#!/usr/bin/env python3
"""Build-time app catalog: localized launchers and verified local RPM selection."""
import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path
import subprocess

# Source directory, stable package/binary name, Spanish name, English name.
APPS = (
    ('BookOS-Settings', 'bookos-settings', 'Ajustes', 'Settings'),
    ('bookos-clock', 'bookos-clock', 'Reloj', 'Clock'),
    ('bookos-calc', 'bookos-calc', 'Calculadora', 'Calculator'),
    ('BookOS-Player', 'bookos-player', 'Reproductor de música', 'Music'),
    ('bookos-store', 'bookos-store', 'Tienda', 'Store'),
    ('bookos-shell', 'bookos-shell', 'Terminal', 'Terminal'),
    ('BookOS-New', 'bookos-new', 'Novedades', "What's New"),
    ('explorer', 'bookos-explorer', 'Archivos', 'Files'),
    ('bookos-notepad', 'bookos-notepad', 'Bloc de notas', 'Notepad'),
    ('system-monitor', 'bookos-system-monitor', 'Monitor del sistema', 'System Monitor'),
    ('fonts', 'bookos-fonts', 'Fuentes', 'Fonts'),
    ('atmos', 'bookos-audio', 'Audio', 'Audio'),
    ('BookOS-Viewer', 'bookos-viewer', 'Visor', 'Viewer'),
    ('BookOS-VoiceRecorder', 'bookos-voicerecorder', 'Grabadora', 'Voice Recorder'),
    ('calendar', 'bookos-calendar', 'Calendario', 'Calendar'),
    ('camera', 'bookos-camera', 'Cámara', 'Camera'),
    ('BookOS-Link/BookOS-Link-PC', 'bookos-connect', 'Book Connect', 'Book Connect'),
    ('lumina', 'bookos-lumina', 'Lumina', 'Lumina'),
    ('remap', 'bookos-teclas', 'Teclas', 'Keys'),
    ('bookos-browser', 'bookos-browser', 'Aether Browser', 'Aether Browser'),
)

GPUI = {'explorer': 'GPUI', 'bookos-notepad': 'GPUI', 'system-monitor': 'GPUI',
        'fonts': '.', 'atmos': 'GPUI'}
COMPARTIDAS = ('plantilla-gpui',)


def tecnologia(folder):
    return 'gpui' if folder in GPUI else 'firefox' if folder == 'bookos-browser' else 'tauri'


def comprobar_fuentes(root):
    for folder, _, _, _ in APPS:
        manifest = (GPUI[folder] + '/Cargo.toml' if folder in GPUI else
                    'construir.sh' if folder == 'bookos-browser' else 'src-tauri/tauri.conf.json')
        if not (root / folder / manifest).is_file():
            raise ValueError(f'Falta la fuente de {folder}: {manifest}')
    for manifest in ('plantilla-gpui/Cargo.toml', 'plantilla-gpui/bookos-ui/Cargo.toml',
                     'fonts/vendor/gpui/crates/gpui/Cargo.toml',
                     'bookos-desktop/Cargo.lock', 'bookos-desktop/crates/bookos-greeter/Cargo.toml',
                     'bookos-desktop/session/greeter/cage/bookos-entrada.patch',
                     'BookOS-Welcome/data/bookos-welcome.spec',
                     'BookOS-Cursor/scripts/build-cursors.sh', 'bookos-sounds/tema/index.theme'):
        if not (root / manifest).is_file():
            raise ValueError(f'Falta una fuente compartida: {manifest}')
    for variante in ('Dark', 'Light', 'Tinted-Dark', 'Tinted-Light'):
        if not (root / 'Icons' / f'BookOS-Icon-Pack-{variante}' / 'index.theme').is_file():
            raise ValueError(f'Falta el tema de iconos {variante}')


def copiar(root, destino, folders=()):
    comprobar_fuentes(root)
    elegidas = tuple(folders) or tuple(app[0] for app in APPS)
    if set(elegidas) - {app[0] for app in APPS}:
        raise ValueError('Aplicación desconocida')
    carpetas = set(elegidas)
    if any(folder in GPUI for folder in elegidas):
        carpetas.update((*COMPARTIDAS, 'fonts'))
    for folder in sorted(carpetas):
        copia = destino / folder
        if copia.exists():
            shutil.rmtree(copia)
        shutil.copytree(root / folder, copia, symlinks=True,
                        ignore=shutil.ignore_patterns('.git', 'target', 'node_modules', 'dist',
                                                     '.build', '.venv', '__pycache__'))
    fuentes = {}
    for folder in sorted(carpetas):
        revision = subprocess.run(['git', '-C', str(root / folder), 'rev-parse', 'HEAD'],
                                  capture_output=True, text=True)
        digest = hashlib.sha256()
        for path in sorted((destino / folder).rglob('*')):
            if path.is_file() or path.is_symlink():
                digest.update(str(path.relative_to(destino / folder)).encode() + b'\0')
                digest.update(str(path.lstat().st_mode).encode() + b'\0')
                digest.update(path.readlink().as_posix().encode() if path.is_symlink()
                              else bytes.fromhex(sha256(path)))
        fuentes[folder] = {'revision': revision.stdout.strip() if revision.returncode == 0 else None,
                           'sha256_fuentes': digest.hexdigest()}
    registro = destino / 'bookos-fuentes.json'
    anteriores = json.loads(registro.read_text()) if folders and registro.exists() else {}
    registro.write_text(json.dumps(anteriores | fuentes, indent=2) + '\n')


def sha256(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def prepare(root, folders=()):
    """Only modifies isolated build copies, preserving each app's bundle files.

    Con `folders`, solo esas: en una construcción parcial desde cero las demás
    no se han copiado y no hay nada que preparar."""
    for folder, package, spanish, english in APPS:
        if folders and folder not in folders:
            continue
        if tecnologia(folder) != 'tauri':
            continue
        tauri = root / folder / 'src-tauri'
        config_path = tauri / 'tauri.conf.json'
        config = json.loads(config_path.read_text())
        config['productName'] = package
        config['mainBinaryName'] = package
        if package == 'bookos-connect':
            config['bundle'].setdefault('icon', ['icons/icon.png'])
            rpm = config['bundle'].setdefault('linux', {}).setdefault('rpm', {})
            rpm.setdefault('depends', []).append('kdeconnectd')
        if package == 'bookos-teclas':
            rpm = config['bundle']['linux']['rpm']
            files = rpm.setdefault('files', {})
            files['/usr/bin/bookos-teclasd'] = '../teclasd/target/release/bookos-teclasd'
            for source, target in (
                ('bookos-teclasd.service', '/usr/lib/systemd/system/'),
                ('org.bookos.Teclas.conf', '/usr/share/dbus-1/system.d/'),
                ('org.bookos.Teclas.service', '/usr/share/dbus-1/system-services/'),
                ('org.bookos.teclas.policy', '/usr/share/polkit-1/actions/'),
                ('bookos-teclasd.quirks', '/usr/share/libinput/50-')):
                files[target + source] = '../teclasd/sistema/' + source
        linux = config.setdefault('bundle', {}).setdefault('linux', {})
        template_path = tauri / 'linux/bookos-iso.desktop.hbs'
        template_path.parent.mkdir(exist_ok=True)
        old_template = linux.get('rpm', {}).get('desktopTemplate')
        template = (tauri / old_template).read_text() if old_template else (
            '[Desktop Entry]\nType=Application\nName={{name}}\nExec={{exec}}\n'
            'Icon={{icon}}\nTerminal=false\nCategories={{categories}}\n'
            '{{#if mime_type}}\nMimeType={{mime_type}}\n{{/if}}\n')
        lines = [line for line in template.splitlines()
                 if not line.startswith(('Name=', 'Name['))]
        lines[1:1] = [f'Name={english}', f'Name[es]={spanish}']
        template_path.write_text('\n'.join(lines) + '\n')
        linux.setdefault('rpm', {})['desktopTemplate'] = 'linux/bookos-iso.desktop.hbs'
        config_path.write_text(json.dumps(config, ensure_ascii=False, indent=2) + '\n')
        # Old titlebars used font glyphs that render as missing-character boxes
        # on the live image. Preserve handlers/labels and use theme-colored SVG.
        html = root / folder / 'src/index.html'
        if html.exists():
            content = html.read_text()
            shapes = {'minimize': '<path d="M5 12h14"/>',
                      'maximize': '<rect x="5" y="5" width="14" height="14" rx="2"/>',
                      'close': '<path d="m6 6 12 12M18 6 6 18"/>'}
            for control, shape in shapes.items():
                svg = ('<svg aria-hidden="true" width="14" height="14" viewBox="0 0 24 24" '
                       'fill="none" stroke="currentColor" stroke-width="1.7" '
                       'stroke-linecap="round">' + shape + '</svg>')
                content = re.sub(r'(<button\b[^>]*\bid="' + control +
                                 r'"[^>]*>)[─☐✕□▢](</button>)',
                                 lambda m: m[1] + svg + m[2], content)
            html.write_text(content)
        if package == 'bookos-settings':
            # Resize handlers must not replace the SVG with a font glyph again.
            script = root / folder / 'src/main.js'
            if script.exists():
                js = script.read_text()
                normal = ('<svg aria-hidden="true" width="14" height="14" viewBox="0 0 24 24" '
                          'fill="none" stroke="currentColor" stroke-width="1.7">'
                          '<rect x="5" y="5" width="14" height="14" rx="2"/></svg>')
                restore = normal.replace('<rect x="5" y="5" width="14" height="14" rx="2"/>',
                                         '<path d="M8 8V4h12v12h-4"/><rect x="4" y="8" width="12" height="12" rx="2"/>')
                js = js.replace("mx.textContent='☐'", 'mx.innerHTML=' + json.dumps(normal))
                js = js.replace("mx.textContent='❐'", 'mx.innerHTML=' + json.dumps(restore))
                js = js.replace("mx.textContent=m?'❐':'☐'", 'mx.innerHTML=m?' + json.dumps(restore) + ':' + json.dumps(normal))
                script.write_text(js)


def record(repo, sources=None):
    entries = []
    fuentes = json.loads((sources / 'bookos-fuentes.json').read_text()) if sources else {}
    for folder, package, spanish, english in APPS:
        matches = []
        for rpm in repo.glob('*.rpm'):
            result = subprocess.check_output(
                ['rpm', '-qp', '--qf', '%{NAME}\t%{VERSION}-%{RELEASE}.%{ARCH}', str(rpm)],
                text=True, stderr=subprocess.DEVNULL)
            name, evra = result.split('\t')
            if name == package:
                matches.append(dict(name=name, nevra=f'{name}-{evra}', file=rpm.name, sha256=sha256(rpm),
                                    tecnologia=tecnologia(folder), fuente=folder, **fuentes.get(folder, {})))
        if len(matches) != 1:
            raise ValueError(f'{package}: expected exactly one freshly built RPM, got {len(matches)}')
        desktop_name = 'com.org.bookos' if package == 'bookos-system-monitor' else package
        payload = subprocess.check_output(['rpm2cpio', str(repo / matches[0]['file'])])
        desktop = subprocess.run(
            ['cpio', '-i', '--to-stdout', f'./usr/share/applications/{desktop_name}.desktop'],
            input=payload, capture_output=True, check=True).stdout.decode()
        if tecnologia(folder) == 'tauri' and not {f'Name={english}', f'Name[es]={spanish}'} <= set(desktop.splitlines()):
            raise ValueError(f'Incorrect launcher names in {package}')
        entries.extend(matches)
    (repo / 'bookos-apps.json').write_text(json.dumps(entries, indent=2) + '\n')


def verify(repo):
    entries = json.loads((repo / 'bookos-apps.json').read_text())
    if len(entries) != len(APPS) or {e['name'] for e in entries} != {a[1] for a in APPS}:
        raise ValueError('Incomplete local app manifest; run iso/build-apps-in-podman.sh')
    for entry in entries:
        if Path(entry['file']).name != entry['file']:
            raise ValueError('Invalid RPM filename')
        if not re.fullmatch(re.escape(entry['name']) + r'-[A-Za-z0-9.+_:~^-]+', entry['nevra']):
            raise ValueError('Invalid RPM version in manifest')
        if sha256(repo / entry['file']) != entry['sha256']:
            raise ValueError(f"RPM changed after build: {entry['name']}")
    return entries


def resign(repo):
    """Acepta el sha256 nuevo de los RPM que se han firmado tras el build.

    Firmar reescribe la cabecera y cambia el sha256, así que verify() los daría
    por manipulados. Solo se acepta el hash nuevo si el RPM verifica con la
    clave de BookOS: lo que haya cambiado lo firmó quien tiene la privada.
    """
    entries = json.loads((repo / 'bookos-apps.json').read_text())
    check = Path(__file__).with_name('check-artifacts.sh')
    for entry in entries:
        rpm = repo / entry['file']
        if sha256(rpm) == entry['sha256']:
            continue
        subprocess.run(['bash', str(check), 'rpm', str(rpm)], check=True, stdout=subprocess.DEVNULL)
        entry['sha256'] = sha256(rpm)
    (repo / 'bookos-apps.json').write_text(json.dumps(entries, indent=2) + '\n')
    verify(repo)


def pin(repo, kickstart):
    entries = verify(repo)
    names = ','.join(e['name'] for e in entries)
    versions = {e['name']: e['nevra'] for e in entries}
    lines = kickstart.read_text().splitlines()
    in_packages = False
    for i, line in enumerate(lines):
        if line.startswith('repo --name=bookos-apps '):
            lines[i] += f' --excludepkgs={names}'
        if line.startswith('%packages'):
            in_packages = True
        elif line == '%end':
            in_packages = False
        elif in_packages and line in versions:
            lines[i] = versions[line]
    kickstart.write_text('\n'.join(lines) + '\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['prepare', 'record', 'verify', 'resign', 'pin', 'list', 'comprobar', 'copiar', 'plan'])
    parser.add_argument('directory', type=Path, nargs='?')
    parser.add_argument('extra', nargs='*', help='kickstart para pin; carpetas para prepare')
    args = parser.parse_args()
    if args.command == 'list':
        for app in APPS:
            print(app[0])
    elif args.command == 'plan':
        for folder, package, _, _ in APPS:
            print(folder, package, tecnologia(folder), GPUI.get(folder, '.'), sep='\t')
    elif args.command == 'comprobar':
        comprobar_fuentes(args.directory)
    elif args.command == 'copiar':
        copiar(args.directory, Path(args.extra[0]), args.extra[1:])
    elif args.command == 'record':
        record(args.directory, Path(args.extra[0]) if args.extra else None)
    elif args.command == 'pin':
        pin(args.directory, Path(args.extra[0]))
    elif args.command == 'prepare':
        prepare(args.directory, args.extra)
    else:
        globals()[args.command](args.directory)
