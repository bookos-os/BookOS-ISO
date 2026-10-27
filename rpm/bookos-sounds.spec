Name:           bookos-sounds
Version:        0.6.5
Release:        1%{?dist}
Summary:        BookOS sound theme
License:        LicenseRef-BookOS
URL:            https://bookos.es/
BuildArch:      noarch
# Tarball with a top-level tema/ dir (index.theme + stereo/*.oga), built by
# check-packages.sh from bookos-sounds/tema, which elegir.py generates.
Source0:        %{name}-%{version}.tar.gz
# index.theme inherits from freedesktop: any event BookOS has no sound for
# falls back to it instead of staying silent.
Requires:       sound-theme-freedesktop

%description
The BookOS XDG sound theme: notifications, lock and unlock, screenshot,
volume, charger, warning and error, login and logout. The BookOS session
selects it as the GTK sound theme when it is installed, and the compositor
plays from it directly.

%prep
%setup -q

%install
install -dm755 %{buildroot}/usr/share/sounds/bookos/stereo
install -m644 tema/index.theme %{buildroot}/usr/share/sounds/bookos/
install -m644 tema/stereo/*.oga %{buildroot}/usr/share/sounds/bookos/stereo/

%files
/usr/share/sounds/bookos/

%changelog
* Tue Oct 20 2026 BookOS <packages@bookos.es> - 0.6.5-1
- 6 dB louder across the theme (-18 LUFS, peak ceiling -1 dBFS); screenshot
  12 dB (-15 LUFS, like lock). The Samsung references sit at -13/-16 LUFS and
  these reached the speaker 6-9 dB under music
- Stereo: near-mono sounds get a decorrelated side channel (velvet noise,
  2-50 ms, above 500 Hz) up to -12 dB side/mid. The mono sum is unchanged
- Ship power-plug and power-unplug: the compositor asks for those names, and
  without them the package fell back to freedesktop's charger sounds

* Thu Oct 15 2026 BookOS <packages@bookos.es> - 0.6.4-1
- Synthesized sounds remastered for laptop speakers (bookos-sounds/remasterizar.py):
  error, warning, login and logout one octave up; harder mallet, FM index and
  harmonics for brightness. Same notes, rhythm, panning, room and loudness

* Thu Oct 15 2026 BookOS <packages@bookos.es> - 0.6.3-1
- Lock and unlock 6 dB louder (-21 LUFS): at -27 they were too quiet

* Thu Oct 15 2026 BookOS <packages@bookos.es> - 0.6.2-1
- Theme regenerated from the selection in bookos-sounds/seleccion.json

* Fri Oct 09 2026 BookOS <packages@bookos.es> - 0.6.1-1
- Initial: BookOS sound theme (14 events, Vorbis, levelled to BS.1770 loudness)
