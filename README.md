# EY6 Control (iOS)

Deine HTML-App als native iOS-App. `Resources/index.html` ist unverändert.
`Resources/bridge.js` ersetzt das fehlende Web Bluetooth durch CoreBluetooth,
inklusive Geräteauswahl, Autoverbinden (Gerät merken, auf Werbepakete warten),
Kopieren/Speichern des Logs und dauerhaftem Speicher für die Einstellungen.

## IPA bauen (kein Mac nötig, GitHub baut sie)

1. Auf github.com ein neues Repository anlegen (privat reicht).
2. Den Inhalt dieses Ordners hochladen, **inklusive** des versteckten Ordners `.github`:
   ```
   git init && git add -A && git commit -m "EY6 Control"
   git branch -M main
   git remote add origin https://github.com/DEIN-NAME/ey6-control.git
   git push -u origin main
   ```
3. Im Repo: **Actions → Build IPA → Run workflow** (läuft auch automatisch beim Push). Dauer ca. 3 Minuten.
4. Fertigen Lauf öffnen, unten unter **Artifacts** `EY6Control-ipa` laden, ZIP entpacken → `EY6Control.ipa`.

## Auf das iPhone (Windows-PC)

1. iTunes und iCloud von apple.com (nicht aus dem Microsoft Store) installieren, iPhone per USB verbinden.
2. Sideloadly öffnen, IPA hineinziehen, Apple-ID eingeben, Start.
3. iPhone: Einstellungen → Allgemein → VPN & Geräteverwaltung → deiner Apple-ID vertrauen.
4. iOS 16+: Einstellungen → Datenschutz & Sicherheit → Entwicklermodus an.
5. Mit kostenloser Apple-ID läuft die App 7 Tage, dann neu installieren (Einstellungen bleiben erhalten, wenn du über die alte App drüber installierst).

Beim ersten Start fragt iOS nach der Bluetooth-Erlaubnis. Bitte zulassen.

## Selbst bauen auf einem Mac

`bash build.sh` → `build/EY6Control.ipa`
