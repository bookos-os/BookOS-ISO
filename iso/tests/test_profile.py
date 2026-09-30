import importlib.util
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("bookos_profile", ROOT / "profile.py")
profile = importlib.util.module_from_spec(spec)
spec.loader.exec_module(profile)


class ProfileTests(unittest.TestCase):
    def test_live_session_requires_an_installed_desktop_file(self):
        raw = profile.render()
        function = re.search(r'^select_live_session\(\) \{.*?^\}', raw, re.M | re.S).group()
        for files, expected in (
            (["wayland-sessions/bookos.desktop", "wayland-sessions/plasma.desktop"], "bookos.desktop"),
            # Plasma ya no es respaldo: sin bookos.desktop el compose falla.
            (["wayland-sessions/plasma.desktop"], None),
            ([], None),
        ):
            with self.subTest(files=files), tempfile.TemporaryDirectory() as tmp:
                for name in files:
                    path = Path(tmp) / name
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.touch()
                result = subprocess.run(
                    ["bash", "-c", function.replace("/usr/share", tmp) + "\nselect_live_session"],
                    text=True, capture_output=True,
                )
                if expected is None:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("wayland-sessions/bookos.desktop (bookos-desktop)", result.stderr)
                else:
                    self.assertEqual(result.returncode, 0)
                    self.assertEqual(result.stdout.strip(), expected)

    def test_generic_boot_and_explicit_extra_arguments(self):
        boot = re.search(r'^bootloader .*$', profile.render(), re.M).group()
        self.assertEqual(boot, 'bootloader --location=mbr --append="rhgb quiet rd.live.image"')
        script = (ROOT / "build-iso.sh").read_text()
        assignment = re.search(r'^EXTRA_BOOT_ARGS=.*$', script, re.M).group()
        for value in (None, "", "debug test_parameter=1"):
            with self.subTest(value=value):
                env = dict(os.environ)
                env.pop("EXTRA_BOOT_ARGS", None)
                if value is not None:
                    env["EXTRA_BOOT_ARGS"] = value
                result = subprocess.run(
                    ["bash", "-uc", assignment + '\nprintf "%s" "$EXTRA_BOOT_ARGS"'],
                    env=env, capture_output=True, text=True, check=True,
                )
                self.assertEqual(result.stdout, value or "")

    def test_all_channels_parse_and_shell_scripts_are_valid(self):
        for channel in ("stable", "beta", "dev"):
            with self.subTest(channel=channel):
                raw = profile.render(channel)
                handler = profile.validate(raw)
                packages = set(handler.packages.packageList)
                self.assertTrue({"bookos-shell", "bookos-player", "bookos-clock", "bookos-notepad", "bookos-calc", "bookos-settings", "bookos-store", "bookos-welcome", "bookos-new", "bookos-explorer", "bookos-desktop", "firefox", "dolphin", "kde-partitionmanager"} <= packages)
                self.assertFalse({"konsole", "bookos-viewer", "bookos-voice-recorder", "openssh-server"} & packages)
                self.assertTrue(handler.packages.excludeWeakdeps)
                self.assertFalse(handler.packages.handleMissing)
                self.assertNotIn("@^kde-desktop-environment", raw)
                self.assertIn("bookos.conf", raw)
                self.assertIn("if [ -f /usr/share/wayland-sessions/bookos.desktop ]", raw)
                self.assertIn("%post --interpreter=/usr/bin/bash --erroronfail", raw)
                self.assertIn('chmod 0755 "$DESK/$(basename "$LAUNCH")"', raw)
                self.assertIn('chmod 0755 "$launcher"', raw)

    def test_iso_wrapper_supports_separate_output_directory(self):
        script = (ROOT / "build-in-podman.sh").read_text()
        self.assertIn('OUTDIR="${OUTDIR:-$ROOT}"', script)
        self.assertIn('-v "$OUTDIR":/out', script)
        self.assertIn('BookOS $CHANNEL $VERSION /out $ALLAPPS', script)

    def test_optional_apps_remain_opt_in(self):
        h = profile.validate(profile.render(apps=["bookos-viewer", "bookos-voice-recorder"]))
        self.assertIn("bookos-viewer", h.packages.packageList)

    def test_invalid_substitutions_are_rejected(self):
        for kwargs in ({"name": 'BookOS"; touch /tmp/bad'}, {"apps": ["foo\n%post"]}, {"channel": "../../other"}):
            with self.assertRaises(ValueError):
                profile.render(**kwargs)

    def test_uefi_entry_selection_uses_label_partition_and_loader(self):
        # Execute the actual parser used by the installer, with firmware output.
        script = (ROOT / "files/bookos-boot-finalize.sh").read_text()
        function = re.search(r"    entry_ids\(\) \{.*?\n    \}", script, re.S).group()
        fixture = """BootOrder: 0001,0007,0008,0009
Boot0001* Windows Boot Manager HD(1,GPT,abcd,0,1)/File(\\EFI\\Microsoft\\Boot\\bootmgfw.efi)
Boot0007* BookOS\tHD(1,GPT,abcd,0,1)/File(\\EFI\\fedora\\shimx64.efi)
Boot0008* BookOS HD(1,GPT,other,0,1)/File(\\EFI\\fedora\\shimx64.efi)
Boot0009* BookOS HD(1,GPT,abcd,0,1)/File(\\EFI\\BOOT\\BOOTX64.EFI)
Boot000A BookOS HD(1,GPT,abcd,0,1)/File(\\EFI\\FEDORA\\SHIMX64.EFI)
"""
        result = subprocess.run(["bash", "-c", "partuuid=abcd\n" + function + "\nentry_ids"], input=fixture, text=True, capture_output=True, check=True)
        self.assertEqual(result.stdout.splitlines(), ["0007", "000A"])

    def test_boot_validation_rejects_incomplete_targets_and_propagates_errors(self):
        for scenario in ("valid", "missing-initramfs", "no-entries", "dracut-failed"):
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                for directory in ("boot/loader/entries", "boot/grub2", "etc/default", "var/log"):
                    (root / directory).mkdir(parents=True, exist_ok=True)
                (root / "etc/default/grub").write_text('GRUB_TIMEOUT=0\n')
                (root / "boot/grub2/grub.cfg").write_text('blscfg\n')
                (root / "boot/vmlinuz-test").write_text('kernel fixture')
                if scenario != "missing-initramfs":
                    (root / "boot/initramfs-test.img").write_text('initramfs fixture')
                if scenario != "no-entries":
                    (root / "boot/loader/entries/test.conf").write_text('title BookOS\nversion test\nlinux /vmlinuz-test\ninitrd /initramfs-test.img\noptions root=UUID=test ro\n')
                # Run the production shell against an isolated target with inert
                # external tools. Never touch the host boot files or firmware.
                script = (ROOT / "files/bookos-boot-finalize.sh").read_text()
                for path in ("/boot", "/etc/default/grub", "/var/log", "/sys/firmware/efi"):
                    script = script.replace(path, tmp + path)
                script = script.replace('/usr/libexec/bookos-apply-identity', 'true')
                script = script.replace('/usr/libexec/bookos-plymouth-language', 'true')
                mocks = """
findmnt() { return 0; }
plymouth-set-default-theme() { return 0; }
grub2-mkconfig() { return 0; }
grub2-script-check() { return 0; }
grub2-editenv() { return 0; }
"""
                mocks += "dracut() { return " + ("3" if scenario == "dracut-failed" else "0") + "; }\n"
                result = subprocess.run(["bash"], input=mocks + script, text=True, capture_output=True)
                log = (root / "var/log/bookos-boot-finalize.log").read_text()
                if scenario == "valid":
                    self.assertEqual(result.returncode, 0, log)
                    self.assertIn('BookOS boot validation completed', log)
                else:
                    self.assertNotEqual(result.returncode, 0, log)
                    self.assertIn('ERROR:', log)
                    self.assertNotIn('BookOS boot validation completed', log)


if __name__ == "__main__":
    unittest.main()
