# Lernordner – Xournal++-Plugin (Xournal++ 1.3.3, Ubuntu/GNOME/Wayland)

Dies ist die öffentliche Version (DE/EN, Konfig ~/.config/xournalpp/lernordner.ini, CC BY-NC-SA 4.0,
Repo theflow85/paper-xournalpp). Eine persönliche Variante mit festen Ordnern wird getrennt gepflegt;
Änderungen daraus werden von Hand nachgezogen.

## Aufbau
- plugin/Lernordner/main.lua – Lua-Plugin, ruft lernordner.py auf (Zeilen `SCHLÜSSEL<TAB>Wert`)
- plugin/Lernordner/lernordner.py – zenity-Dialoge, Dateien anlegen/kopieren/prüfen, Papierkorb
- bin/lerntags (main) bzw. plugin/Lernordner/lerntags.py (public) – Tag-Suche
- einrichten.py – settings.xml / toolbar.ini / .desktop; install.sh / uninstall.sh mit Backups

## Belegte API-Fakten (Quellcode 1.3.3) – nicht "verbessern"
- Kein app.activateAction/changeActionState in initUi: actionDB existiert dort noch nicht → Absturz.
- app.openFile(p, n, true) verwirft Ungespeichertes → vorher speichern und auf die Datei warten
  (Inode/mtime/Größe stabil, kein "~"-Backup, Datei endet auf </xournal>).
- PDF-.xopp: erste Seite `<background type="pdf" domain="absolute" filename="./X.pdf" pageno="1"/>`, weitere nur pageno.
- Symbole nach ~/.local/share/icons/hicolor/scalable/actions (Xournals eigenes index.theme kennt nur */actions).
- Unbekannte Aktionsnamen werden zu "new-file" (Action_fromString) – Namen exakt prüfen.
- Titel = Sans 22 #1a1a1a, Tag-Zeile = Sans 10 #808080 (Erkennungsmerkmal).

## Hochformat: Leiste und Dock (2026-11-15, aus main nachgezogen)
- Zweites Layout [Lernmodus hoch] in toolbar.ini (einrichten.py, LEISTE_HOCH): gleicher Inhalt, aber
  `toolbarTop1` statt `toolbarLeft1`. Die Etikett-Zeile steht in mainBox an Position 0 (über tbTop1/tbTop2).
- In public ist die Lernmodus-Leiste freiwillig (`--leiste`): Umschalten nur, wenn „Lernmodus“ oder
  „Lernmodus hoch“ gewählt ist – eine eigene Leiste des Nutzers bleibt unberührt (`lernordner.py leiste` und
  `leiste_pruefen` in main.lua prüfen das).
- Start: `lernordner.py leiste` (vom Starter, nur wenn xournalpp nicht läuft) liest die Drehung per
  `gdbus … org.gnome.Mutter.DisplayConfig GetCurrentState` (transform 1/3/5/7 = hoch), setzt selectedToolbar
  (Sicherung settings.xml.vor-start beim ersten Mal) und gibt „hoch“/„quer“ aus.
- Laufzeit: `leiste_pruefen` (Beobachter, alle 2 s, 2 Takte stabil) liest die Monitorgröße (Gdk) und löst über lgi
  die Fensteraktion `win.select-toolbar` mit dem Layoutnamen aus (Typ "s", belegt; Log „Leiste:“).
- Ubuntu-Dock: nur wenn bei der Installation gewählt (Frage im Custom-Modus, nur mit dash-to-dock; Standard
  nein). install.sh setzt `@DOCK@` im Starter. Quer `dock-fixed true`, hoch `false`, solange Xournal++ läuft; der
  Starter (Elternprozess statt `exec`) stellt beim Ende den vorherigen Wert wieder her und exportiert
  LERNORDNER_DOCK=1, erst dann schaltet das Plugin beim Drehen mit um. Bei kill -9 des Starters bleibt es
  → `gsettings reset org.gnome.shell.extensions.dash-to-dock dock-fixed`.

## Knöpfe nur/auch in public (2026-11-15)
- 🗑 Verwerfen (`lernVerwerfen`, `lernordner.py verwerfen`): auch in main. Frage → neues Blatt (openFile(…, true))
  → alte Datei erst danach in den Papierkorb. Test am Ende von tests/test_etikett.lua.
- ⟳ Dreh-Schalter (LERN_DREHEN, `lernDrehen`) NUR in public: Zustand in ~/.local/state/lernordner/drehen
  (`lernordner.py drehen an|aus|umschalten|status`; fehlt die Datei = aus). install.sh fragt in Standard UND Custom und
  schreibt die Datei. `leiste` (Start) und `leiste_pruefen` (Laufzeit, auch Dock) tun nur etwas, wenn „an“.
  Das Symbol (lernordner-drehen / -drehen-aus) setzt `drehen_symbol` nach jedem Umbau der Leiste neu.
  Der Starter merkt sich das Dock immer (DOCK_OPTION=1), damit späteres Einschalten funktioniert.
- LEISTE_INHALT in einrichten.py unterscheidet sich von main (zusätzlich LERN_DREHEN) → beim Merge von main Konflikt
  erwartbar; Toolbar-Texte/Kommentare in public Englisch, `_()`-Tabelle TEXTE in lernordner.py.
- Lizenz: CC BY-NC-SA 4.0 (LICENSE = offizieller Text, unverändert; Urhebervermerk + Haftungsausschluss in den
  READMEs).
- install-lgi.sh: baut lgi für Lua 5.4 nach ~/.local (Rezept aus der Shell-Historie des Entwicklers).

## Tests
`luac -p plugin/Lernordner/main.lua`; Python per py_compile; Abläufe mit Fake-zenity und Lua-Mock der
app-API (siehe Verlauf im Projekt „xournalplugin“). GUI/Stift/Vollbild nur am Gerät testbar.
