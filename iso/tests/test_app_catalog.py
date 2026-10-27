import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('catalog', Path(__file__).resolve().parents[1] / 'app-catalog.py')
catalog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(catalog)


class AppCatalogTests(unittest.TestCase):
    def test_prepare_keeps_launch_commands_and_bundle_resources(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for folder, package, spanish, english in catalog.APPS:
                if catalog.tecnologia(folder) != 'tauri':
                    continue
                source = root / folder
                tauri = source / 'src-tauri'
                (tauri / 'linux').mkdir(parents=True)
                (source / 'src').mkdir()
                (source / 'src/index.html').write_text('<button id="maximize" aria-label="Maximizar">☐</button>')
                (source / 'src/main.js').write_text("mx.textContent='☐';mx.textContent='❐';if(mx)mx.textContent=m?'❐':'☐';")
                (tauri / 'linux/desktop.hbs').write_text('[Desktop Entry]\nName=Old\nName[es]=Viejo\nExec={{exec}} %F\nMimeType=text/plain;\n')
                (tauri / 'tauri.conf.json').write_text(json.dumps({'version': '1.2.3', 'bundle': {'linux': {'rpm': {'desktopTemplate': 'linux/desktop.hbs', 'files': {'/usr/share/app/data': 'data'}}}}}))
            catalog.prepare(root)
            for folder, package, spanish, english in catalog.APPS:
                if catalog.tecnologia(folder) != 'tauri':
                    continue
                config = json.loads((root / folder / 'src-tauri/tauri.conf.json').read_text())
                template = (root / folder / 'src-tauri/linux/bookos-iso.desktop.hbs').read_text()
                self.assertIn(f'Name[es]={spanish}\n', template)
                self.assertIn('Exec={{exec}} %F\n', template)
                self.assertIn('MimeType=text/plain;', template)
                self.assertEqual(config['version'], '1.2.3')
                self.assertEqual(config['bundle']['linux']['rpm']['files']['/usr/share/app/data'], 'data')
                self.assertIn('<svg', (root / folder / 'src/index.html').read_text())
                if package == 'bookos-settings':
                    script = (root / folder / 'src/main.js').read_text()
                    self.assertNotIn('mx.textContent', script)
                    self.assertIn('mx.innerHTML=m?', script)

    def test_se_elige_gpui_y_se_conservan_los_servicios_necesarios(self):
        self.assertEqual(set(catalog.GPUI), {'explorer', 'bookos-notepad', 'system-monitor', 'fonts', 'atmos'})
        self.assertEqual(len({app[1] for app in catalog.APPS}), len(catalog.APPS))
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for folder in ('remap', 'BookOS-Link/BookOS-Link-PC'):
                tauri = root / folder / 'src-tauri'
                tauri.mkdir(parents=True)
                (tauri / 'tauri.conf.json').write_text(json.dumps({'bundle': {'linux': {'rpm': {}}}}))
            catalog.prepare(root, ('remap', 'BookOS-Link/BookOS-Link-PC'))
            teclas = json.loads((root / 'remap/src-tauri/tauri.conf.json').read_text())['bundle']['linux']['rpm']
            self.assertIn('/usr/bin/bookos-teclasd', teclas['files'])
            self.assertIn('/usr/share/polkit-1/actions/org.bookos.teclas.policy', teclas['files'])
            link = json.loads((root / 'BookOS-Link/BookOS-Link-PC/src-tauri/tauri.conf.json').read_text())
            self.assertIn('kdeconnectd', link['bundle']['linux']['rpm']['depends'])

    def test_manifest_rejects_missing_and_changed_apps_and_excludes_remote(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp)
            entries = []
            for _, name, _, _ in catalog.APPS:
                rpm = repo / f'{name}.rpm'
                rpm.write_bytes(name.encode())
                entries.append({'name': name, 'nevra': name + '-1.0-1.x86_64', 'file': rpm.name, 'sha256': catalog.sha256(rpm)})
            manifest = repo / 'bookos-apps.json'
            manifest.write_text(json.dumps(entries))
            catalog.verify(repo)
            ks = repo / 'test.ks'
            ks.write_text('repo --name=bookos-apps --baseurl=https://example.org/\nrepo --name=fedora --baseurl=https://example.org/\n%packages\nbookos-settings\n%end\n')
            catalog.pin(repo, ks)
            self.assertIn('--excludepkgs=bookos-settings,', ks.read_text())
            self.assertIn('\nbookos-settings-1.0-1.x86_64\n', ks.read_text())
            self.assertEqual(ks.read_text().splitlines()[1], 'repo --name=fedora --baseurl=https://example.org/')
            manifest.write_text(json.dumps(entries[:-1]))
            with self.assertRaises(ValueError):
                catalog.verify(repo)
            manifest.write_text(json.dumps(entries))
            (repo / entries[0]['file']).write_bytes(b'changed')
            with self.assertRaises(ValueError):
                catalog.verify(repo)
