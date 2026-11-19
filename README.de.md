# Lernordner – Lernmodus für Xournal++

*[English version](README.md)*

Ein Xournal++-Plugin für handschriftliche Lernnotizen mit dem Stift: Kapitelnotizen, markierte
PDFs, Tags und Ablage – **ohne jemals den Speicherdialog zu sehen**. Entstanden für die
Prüfungsvorbereitung auf einem Convertible, nutzbar für jedes Fach.

<!-- Screenshot: docs/screenshot.png -->

## Was du bekommst

Wie Papier: Es ist genau ein Zettel offen, und er hat immer eine Datei – **nie ein Speicherdialog**.

- **＋ Neu** – ein frisches Blatt im Eingang; der Cursor springt in die **Etikett-Leiste** oben:
  `01 Ordner / 003 Name · #tag #tag`. Tippen filtert die Ordnerliste (↓/↑ wählen, → oder Enter
  übernehmen und weiter), dann der Name (freie Kapitel aus deiner Kapitelliste werden angeboten),
  dann die Tags. Tippen auf die Seite beendet. Ordner und Name werden einmal übernommen, kurz mit „↶ Rückgängig“.
- **Nummern pro Ordner** – Ordner heißen `NN Name` (neuer Ordner = nächste Nummer), Zettel in
  nummerierten Ordnern `NNN Titel` (nächste freie Nummer im Ordner oder die Nummer eines passenden
  Kapitels). Eingang (`00`), `10` und `99` bleiben ohne Zettelnummern.
- **Tags als Kästchen** – Leertaste oder Komma machen aus einem Wort `#tag ×`; Vorschläge aus deinen Tags.
  Tags stehen unsichtbar über der Seite (nicht gezeichnet, nicht exportiert); `#Wörter` in normalen
  Textfeldern zählen mit. Eine Seite ohne Tags zeigt einen dezenten gelben Hinweis.
- **📂 Öffnen** – zuletzt geöffnete Zettel, dann Ordner → Zettel/Kapitel, „＋ Neues Kapitel“, Tag-Suche, PDF-Import.
- **Neue Seite** – grünes ＋ am Dokumentende, daneben die Seitenart der aktuellen Seite
  (liniert / kariert / Punkte / leer). Vor einer neuen Seite nach einer Seite ohne Tags erinnert es einmal.
- **Dicke & Farbe** – ein stifttaugliches Menü für Strichstärke und Farben.
- **🗑 Verwerfen** – wirft die offene Notiz weg, bevor du schließt: fragt nach, öffnet ein frisches Blatt und legt
  die alte Datei in den Papierkorb (`.papierkorb` im Notizordner) – nie endgültig gelöscht.
- **⟳ Dreh-Schalter** – Knopf in der Leiste: die Leiste folgt der Bildschirmdrehung (siehe *Hochformat*).
- **GNOME-Suche** – <kbd>Super</kbd> drücken und Tag, Name oder Ordner tippen; passende Zettel erscheinen
  als eigene Gruppe (zusätzlich zu den üblichen Treffern) und öffnen sich in Xournal++.
- Automatisches Speichern der echten Datei (jede Minute, wenn das Fenster den Fokus verliert, vor dem
  Ruhezustand); leere Blätter werden nie aufgehoben; der nächste Start öffnet den letzten Zettel.
- Ein Starter (PDF aus dem Dateimanager öffnen = importieren) und `lerntags`, ein kleines
  Kommandozeilenwerkzeug, das Tags auflistet und findet.

## Voraussetzungen

- Linux, **Xournal++ 1.3.x** (geschrieben gegen die Plugin-API von 1.3.3)
- `python3`, `python3-gi`, `zenity`, `poppler-utils` (für `pdfinfo`)
  `sudo apt install zenity poppler-utils python3-gi`
- **`lua-lgi` für die Lua-Version von Xournal++ (5.4)** – nötig für Etikett-Leiste, 📂 Öffnen und das
  Menü Dicke & Farbe. Ubuntu liefert lgi nur für Lua 5.1/5.3; lgi 0.9.2 für 5.4 selbst bauen und nach
  `~/.local/share/lua/5.4` und `~/.local/lib/lua/5.4` installieren (dort sucht das Plugin). `bash install-lgi.sh`
  macht genau das (braucht `sudo apt install build-essential pkg-config git liblua5.4-dev libgirepository1.0-dev`).

Entwickelt unter Ubuntu mit GNOME (Wayland) auf einem Convertible mit Stift. Andere Desktops sollten gehen – Rückmeldungen willkommen.

## Installation

Xournal++ schließen, dann:

```bash
git clone https://github.com/theflow85/xournalpp-lernordner.git
cd xournalpp-lernordner
bash install.sh
```

Der Installer fragt zuerst, ob die Leiste der Bildschirmdrehung folgen soll, dann eine Sache:

- **Standard** (empfohlen, nur die eine Frage zur Drehung): Notizen in `~/Dokumente/Lernordner`,
  Lernmodus-Leiste aktiv, Starter, Touchscreen nur scrollen/zoomen, Autosave alle 2 Minuten,
  gelber halbtransparenter Marker, Vollbild ohne Menü und Seitenleiste.
- **Custom**: Ordner und jede dieser Einstellungen selbst wählen.

Alle geänderten Dateien werden in `~/.config/xournalpp/lernordner-backups/` gesichert.
Das Plugin ist automatisch aktiv; einfach Xournal++ starten.

## Zurück zur normalen Oberfläche

<kbd>F10</kbd> (Menü einblenden) → **Bearbeiten → Werkzeugleisten → Xournal++**. Zurück genauso: **Lernmodus**.
<kbd>F11</kbd> schaltet den Vollbild-Modus um.

## Hochformat (Tablet / Convertible)

Bei aktiver Lernmodus-Leiste liegt sie im Querformat links und wandert im Hochformat nach oben (die
Etikett-Leiste bleibt darüber). Sie folgt der Drehung des Bildschirms auch bei laufendem Xournal++; der Installer
fragt, ob du das willst, und der **⟳-Knopf** in der Leiste schaltet es jederzeit ein und aus. Hast du eine
eigene Leiste gewählt, wird nichts angefasst. Bei der **Custom**-Installation (GNOME mit Ubuntu-Dock)
kannst du zusätzlich wählen, dass das Dock im Querformat fest bleibt und sich im Hochformat ausblendet,
solange Xournal++ läuft; beim Beenden wird es wiederhergestellt. Bleibt das Dock einmal verstellt
(z. B. nach einem Absturz des Starters): `gsettings reset org.gnome.shell.extensions.dash-to-dock dock-fixed`.

## Kapitelliste (optional)

Der Kapitel-Knopf braucht eine Tabulator-getrennte Datei `~/.config/xournalpp/lernordner-kapitel.tsv`:

```
# Nummer<TAB>Ordner<TAB>Titel
1	01 Grundlagen	Einführung
2	01 Grundlagen	Kommunikation
17	02 Symptome	Bauchschmerzen
```

Die Ordner-Spalte fasst Kapitel zu Teilen zusammen; Ordner entstehen bei der ersten Nutzung.
Beispiele in [`examples/`](examples/). Ohne Liste funktioniert alles andere wie gewohnt.

## Sicherheit

- Es wird nie etwas gelöscht. Ablegen speichert erst, wartet, bis Xournal++ fertig geschrieben hat,
  kopiert, prüft die Kopie Byte für Byte, öffnet sie – und verschiebt erst dann das Original in
  den versteckten Ordner `.papierkorb` im Notizordner.
- Bei jedem Fehler bleibt das Original, wo es ist.
- Unberührte leere Notizen im Eingang, die älter als einen Tag sind, wandern ebenfalls in den Papierkorb.

## Deinstallation

Xournal++ schließen, dann `bash uninstall.sh`. Es stellt die gesicherten Einstellungen wieder her; deine Notizen bleiben.

## Bekannte Grenzen

- Kein Vollbild-Knopf: Unter GNOME 50 reagiert der Stift im Vollbild nicht mehr, nachdem er kurz den
  Bildschirm verlassen hat. Das Fenster läuft stattdessen maximiert ohne Titelleiste (Knöpfe rechts in der Etikett-Leiste).
- Die Ordnersuche im Dateimanager (Nautilus) sieht keine Tags: GNOMEs Indexer liest den Inhalt von `.xopp`
  nicht. Dafür die Übersichtssuche (<kbd>Super</kbd>) nehmen; der Suchanbieter wirkt nach dem nächsten Anmelden.
- Konfiguration: `~/.config/xournalpp/lernordner.ini` (Ordner, Name des Eingangs, Kapitelliste).
  Logs: `~/.cache/lernordner.log`, `~/.cache/lernordner-suche.log`.

## Wie es funktioniert

Xournal++ zeigt den Speicherdialog nur, wenn ein Dokument keinen Dateipfad hat. Lernordner legt
deshalb jede Notiz zuerst als Datei an (aus `template.xopp` bzw. als erzeugte `.xopp` mit dem PDF
als Hintergrund) und öffnet diese. Das Lua-Plugin steuert Xournal++; ein Python-Helfer erledigt
Dialoge (zenity) und Dateiarbeit.

## Lizenz und Haftungsausschluss

Copyright © 2026 theflow85. Lizenziert unter **Creative Commons Namensnennung – Nicht kommerziell – Weitergabe
unter gleichen Bedingungen 4.0 International** (CC BY-NC-SA 4.0) – siehe [LICENSE](LICENSE) bzw.
<https://creativecommons.org/licenses/by-nc-sa/4.0/deed.de>. Kurz: Nutzen, Weitergeben und Bearbeiten sind zu
**nicht kommerziellen** Zwecken erlaubt, mit Namensnennung; Bearbeitungen müssen unter derselben Lizenz stehen.
(Maßgeblich ist der englische Lizenztext in `LICENSE`.)

**Haftungsausschluss.** Diese Software wird „wie besehen“ ohne jede Gewährleistung bereitgestellt. Sie legt Dateien
in deinem Notizordner an, verschiebt, kopiert und löscht sie (Papierkorb) und ändert Einstellungen von Xournal++
(es werden Sicherungen angelegt, garantiert wird aber nichts). **Mach eigene Sicherungen deiner Notizen.** Der
Autor haftet nicht für Datenverlust oder sonstige Schäden. Nutzung auf eigene Gefahr. Kein medizinisches oder
professionelles Produkt. Das Projekt steht in keiner Verbindung zu Xournal++, GNOME oder Ubuntu und wird von
diesen nicht unterstützt; „Xournal++“ gehört seinen Autoren und wird hier nur genannt, um zu beschreiben, womit
das Plugin arbeitet.
