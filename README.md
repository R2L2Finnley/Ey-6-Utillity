# Egret EY! 6 Utility (iOS)

Eine **iOS-App** zur Anzeige von Telemetriedaten, zur Bedienung von Standardfunktionen, zur Protokollierung (Logs) sowie zur Bluetooth-Diagnose für den **Egret EY! 6** E-Scooter.

> **Wichtiger Hinweis:** Dieses Projekt hat **nichts mit Tuning** (wie Geschwindigkeits- oder Leistungsmanipulation) zu tun. Es dient ausschließlich der Anzeige, Steuerung regulärer Funktionen, Protokollierung und Diagnose über Bluetooth.

---

## Vorschau

![Egret EY! 6 App Ansichten](715153463-7aa898ac-75bc-4708-a2bb-22e6e42b9a3d.jpeg)

---

## Funktionsübersicht

Die Oberfläche ist in vier Bereiche unterteilt:

* **Übersicht:** Zeigt einen Tacho (0–40 km/h), den Verbindungsstatus/Scan-Steuerung, den Schnellzugriff für **Air Lock** sowie **Live-Daten** (Akku, Fahrmodus, Geschwindigkeit).
* **Einstellung:**
  * **Fahrmodus:** Auswahl zwischen *Eco (Stufe 1)*, *Drive (Stufe 2)* und *Sport (Stufe 3)* (mit Hinweis, dass die Zuordnung der Stufen auf Annahmen basiert und der Roller die Stufe selbst meldet).
  * **Einheit:** Umschaltung zwischen `km/h` und `mph` (mit Hinweis, dass der Roller Rohwerte liefert und die Anzeige entsprechend umrechnet).
  * **Air Lock:** Sperren und Entsperren.
  * **Autoverbinden:** Option für automatische Verbindung.
* **Logs (Protokoll):** Zeitgestempeltes Protokoll, optionales Live-Mitschreiben von Frames sowie Buttons zum **Kopieren**, **Speichern** und **Leeren**.
* **Diagnose:**
  * **Funkverbindung:** Verbindungsstatus, empfangene Frames, Frames pro Sekunde, verworfene Bytes (kaputte Pakete) sowie Aktionen zum direkten Abfragen des Status und Lesen von Gerätedaten.
  * **Statusframe Byte für Byte:** Tabellenansicht (`#`, `HEX`, `DEZ`, `BINÄR`, `MIN-MAX`, `BEDEUTUNG`) – gelb markierte Bytes zeigen Änderungen innerhalb der letzten 3 Sekunden an und werden zusätzlich im Log vermerkt (z. B. um Bit-Zustände wie einen Tempomat nachzuvollziehen).
  * **Alle empfangenen Funktionen & Gerätedaten (Bluetooth):** Übersicht empfangener Funktionen, Zähler, Daten, CRC/RCC sowie Bluetooth-Gerätedaten.

---

## Projektstruktur & Funktionsweise

Das Projekt kombiniert native iOS-/Swift-Komponenten mit einer Web-Oberfläche (`WKWebView` / HTML+JS):

* **`Sources/AppDelegate.swift`:** Einstiegspunkt / Lebenszyklus der iOS-App.
* **`Sources/WebViewController.swift`:** Verwaltet die Web-Ansicht, in der `index.html` dargestellt wird, und verbindet die Oberfläche mit der nativen Schicht.
* **`Sources/BLEBridge.swift`:** Übernimmt die Bluetooth-Kommunikation (Scannen, Verbinden, Senden/Empfangen von Daten und Frames) und reicht Ereignisse an die UI weiter.
* **`Sources/DevicePicker.swift`:** Auswahl bzw. Verwaltung von Geräten für die Verbindung.
* **`Resources/index.html`:** Enthält das Layout, Styling und die Logik für die vier Tabs (*Übersicht*, *Einstellung*, *Diagnose*, *Logs*) sowie die Byte-/Frame-Auswertung.
* **`Resources/bridge.js`:** Kommunikationsbrücke zwischen JavaScript (`index.html`) und dem nativen iOS-/Bluetooth-Code.
* **`Resources/Info.plist` & `Resources/Assets.xcassets/`:** App-Konfiguration, App-Icon (`AppIcon.appiconset`) und Launch-Hintergrund (`LaunchBG.colorset`).
* **`build.sh` & `.github/workflows/build-ipa.yml`:** Skript bzw. Workflow zum Erstellen des iOS-App-Pakets (`.ipa` / `Payload/EY6Utility.app`).

---

## Plattform & Installation

* **Plattform:** Ausschließlich **iOS / iPhone** (keine Windows-Version oder Desktop-Anwendung).
* **Installation:** Über Xcode / Build-Workflow bzw. Sideloading der erstellten `.ipa`-Datei auf einem iPhone.
