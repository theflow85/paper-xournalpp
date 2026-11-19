#!/usr/bin/env bash
# Installs the Xournal++ plugin "Lernordner" (study mode).
# Installiert das Xournal++-Plugin "Lernordner" (Lernmodus).
#
#   bash install.sh             asks: Standard or Custom
#   bash install.sh --standard  no questions
#
# Close Xournal++ first. All changed files are backed up.
set -euo pipefail

QUELLE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}/xournalpp"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
PLUGIN="$CFG/plugins/Lernordner"
BIN="$HOME/.local/bin"
APPS="$DATA/applications"
ICONS="$DATA/icons/hicolor/scalable/actions"
BACKUPS="$CFG/lernordner-backups"
ERSTE="$BACKUPS/before-first-install"
B="$BACKUPS/$(date +%Y-%m-%d_%H-%M-%S)"

case "${LERNORDNER_LANG:-${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}}" in de*) DE=1 ;; *) DE= ;; esac
m()    { if [ -n "$DE" ]; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi; }
info() { printf '\033[1m%s\033[0m\n' "$(m "$1" "$2")"; }
warn() { printf '\033[33m%s\033[0m %s\n' "$(m Hinweis: Note:)" "$(m "$1" "$2")"; }
fail() { printf '\033[31m%s\033[0m %s\n' "$(m Fehler: Error:)" "$(m "$1" "$2")" >&2; exit 1; }
frage() {  # question-de question-en default(j/n) -> 0 = yes
  local antwort standard="$3"
  read -r -p "$(m "$1" "$2") [$( [ "$standard" = j ] && m "J/n" "Y/n" || m "j/N" "y/N")] " antwort || true
  antwort="${antwort:-$standard}"
  case "$antwort" in [jJyY]*) return 0 ;; *) return 1 ;; esac
}

# ---- checks ---------------------------------------------------------------------
if pgrep -x xournalpp >/dev/null 2>&1 || pgrep -x xournalpp-wrapper >/dev/null 2>&1; then
  fail "Xournal++ läuft noch. Bitte schließen und erneut starten." \
       "Xournal++ is still running. Please close it and run again."
fi
command -v python3 >/dev/null || fail "python3 fehlt." "python3 is missing."
command -v zenity  >/dev/null || fail "zenity fehlt:  sudo apt install zenity" "zenity is missing:  sudo apt install zenity"
command -v pdfinfo >/dev/null || warn "pdfinfo fehlt (sudo apt install poppler-utils) – der PDF-Knopf zeigt dann den Speicherdialog." \
                                     "pdfinfo is missing (sudo apt install poppler-utils) – the PDF button will then show the save dialog."
if command -v xournalpp >/dev/null; then
  V=$(xournalpp --version 2>/dev/null | head -1 || true)
  case "$V" in *1.3.*) ;; *) warn "Getestet mit Xournal++ 1.3.x, gefunden: ${V:-?}" "Tested with Xournal++ 1.3.x, found: ${V:-?}" ;; esac
fi

SYS_DESKTOP=""
for d in /usr/share/applications /usr/local/share/applications; do
  if [ -f "$d/com.github.xournalpp.xournalpp.desktop" ]; then SYS_DESKTOP="$d/com.github.xournalpp.xournalpp.desktop"; break; fi
done
[ -n "$SYS_DESKTOP" ] || SYS_DESKTOP=$(grep -ls '^Exec=xournalpp' /usr/share/applications/*.desktop 2>/dev/null | head -1 || true)

# ---- Standard or Custom -------------------------------------------------------------
ART=standard
if [ "${1:-}" != "--standard" ] && [ -t 0 ]; then
  echo
  m "Installationsart:" "Installation type:"
  m "  [S] Standard – empfohlen: Lernmodus-Leiste (maximiert, ohne Menü), Starter, Touch nur scrollen," \
    "  [S] Standard – recommended: study toolbar (maximised, no menu), launcher, touch only scrolls,"
  m "                Autosave, gelber Marker, GNOME-Suche. Ordner: Dokumente/Lernordner" \
    "                autosave, yellow highlighter, GNOME search. Folder: Documents/Study notes"
  m "  [C] Custom   – Ordner und jede Einstellung einzeln wählen" \
    "  [C] Custom   – choose folder and each setting yourself"
  read -r -p "$(m "Auswahl [S/c]: " "Choice [S/c]: ")" a || true
  case "${a:-s}" in [cC]*) ART=custom ;; esac
fi

BASIS_WAHL=""
OPT_STARTER=1; OPT_LERNTAGS=1; OPT_SUCHE=1; OPT_DOCK=; OPT_DREHEN=an; SETTINGS_OPT=(--leiste --touch --autosave --marker --vollbild)
# Asked in both modes (Standard and Custom)
frage "Leiste im Hochformat nach oben, folgt der Drehung des Bildschirms (ein/aus später per Knopf in der Leiste)?" \
      "Move the toolbar to the top in portrait and follow the screen rotation (switch on/off later with a button in the toolbar)?" j || OPT_DREHEN=aus
if [ "$ART" = custom ]; then
  STD_BASIS=$(python3 "$QUELLE/plugin/Lernordner/lernordner.py" standardbasis 2>/dev/null | sed -n 's/^BASIS\t//p' || true)
  read -r -p "$(m "Basisordner [$STD_BASIS]: " "Base folder [$STD_BASIS]: ")" BASIS_WAHL || true
  SETTINGS_OPT=()
  frage "Lernmodus-Leiste aktivieren (maximiert, ohne Menü/Seitenleiste)?" "Activate the study toolbar (maximised, no menu/sidebar)?" j && SETTINGS_OPT+=(--leiste)
  frage "Xournal++-Starter: jede Sitzung beginnt mit neuer Notiz im Eingang, PDFs landen im Eingang?" \
        "Xournal++ launcher: every session starts with a new note in the inbox, PDFs go to the inbox?" j || OPT_STARTER=
  if [ "$OPT_DREHEN" = an ] && [ -n "$OPT_STARTER" ] && command -v gsettings >/dev/null 2>&1 \
     && gsettings get org.gnome.shell.extensions.dash-to-dock dock-fixed >/dev/null 2>&1; then
    frage "Ubuntu-Dock im Hochformat ausblenden, im Querformat fest lassen (nur solange Xournal++ läuft)?" \
          "Hide the Ubuntu dock in portrait, keep it fixed in landscape (only while Xournal++ runs)?" n && OPT_DOCK=1
  fi
  frage "Touchscreen nur zum Scrollen/Zoomen (Handballen malt nicht)?" "Touchscreen only scrolls/zooms (palm does not draw)?" j && SETTINGS_OPT+=(--touch)
  frage "Autosave alle 2 Minuten?" "Autosave every 2 minutes?" j && SETTINGS_OPT+=(--autosave)
  frage "Marker gelb und halbtransparent?" "Yellow translucent highlighter?" j && SETTINGS_OPT+=(--marker)
  frage "Vollbild (F11) ohne Menü und Seitenleiste?" "Fullscreen (F11) without menu and sidebar?" j && SETTINGS_OPT+=(--vollbild)
  frage "Zweite Stifttaste als großer Radierer?" "Second pen button as a big eraser?" n && SETTINGS_OPT+=(--stifttaste)
  frage "Befehl 'lerntags' im Terminal bereitstellen?" "Provide the 'lerntags' terminal command?" j || OPT_LERNTAGS=
  frage "Notizen über die GNOME-Suche finden (Tags, Namen)?" "Find notes via GNOME search (tags, names)?" j || OPT_SUCHE=
fi
if [ -n "$OPT_STARTER" ] && [ -z "$SYS_DESKTOP" ]; then
  warn "System-Starter von Xournal++ nicht gefunden – Starter wird übersprungen." \
       "Xournal++ system launcher not found – skipping launcher."
  OPT_STARTER=
fi
DESKTOP_NAME=$(basename "${SYS_DESKTOP:-com.github.xournalpp.xournalpp.desktop}")

# ---- backups --------------------------------------------------------------------------
info "Backups nach $B" "Backups in $B"
mkdir -p "$B"
sichere() { if [ -e "$1" ]; then cp -a "$1" "$B/$2"; else : > "$B/$2.missing"; fi; }
sichere "$CFG/settings.xml" settings.xml
sichere "$CFG/toolbar.ini"  toolbar.ini
sichere "$APPS/$DESKTOP_NAME" desktop
if [ -d "$PLUGIN" ]; then cp -a "$PLUGIN" "$B/plugin"; fi
echo "$DESKTOP_NAME" > "$B/desktop-name"
[ -d "$ERSTE" ] || cp -a "$B" "$ERSTE"

# ---- plugin ----------------------------------------------------------------------------
info "Plugin nach $PLUGIN" "Plugin into $PLUGIN"
mkdir -p "$PLUGIN" "$HOME/.cache"
for f in plugin.ini main.lua template.xopp; do install -m 644 "$QUELLE/plugin/Lernordner/$f" "$PLUGIN/$f"; done
for f in lernordner.py lerntags.py; do install -m 755 "$QUELLE/plugin/Lernordner/$f" "$PLUGIN/$f"; done

INIT=$(python3 "$PLUGIN/lernordner.py" init "$BASIS_WAHL")
python3 "$PLUGIN/lernordner.py" drehen "$OPT_DREHEN" >/dev/null   # rotation switch: an / aus
BASIS=$(printf '%s\n' "$INIT" | sed -n 's/^BASIS\t//p')
KONFIG=$(printf '%s\n' "$INIT" | sed -n 's/^KONFIG\t//p')
echo "  $(m Ordner: Folder:) $BASIS   ($(m Konfiguration: Config:) $KONFIG)"

mkdir -p "$ICONS"
install -m 644 "$QUELLE"/icons/*.svg "$ICONS/"
if [ -f "$DATA/icons/hicolor/icon-theme.cache" ] && command -v gtk-update-icon-cache >/dev/null; then
  gtk-update-icon-cache -f -t "$DATA/icons/hicolor" >/dev/null 2>&1 || true
fi

if [ -n "$OPT_LERNTAGS" ]; then
  mkdir -p "$BIN"
  if [ ! -e "$BIN/lerntags" ] || [ -L "$BIN/lerntags" ]; then
    ln -sfn "$PLUGIN/lerntags.py" "$BIN/lerntags"
  else
    warn "$BIN/lerntags existiert schon und bleibt unverändert." "$BIN/lerntags already exists and is left alone."
  fi
fi

# ---- launcher --------------------------------------------------------------------------
if [ -n "$OPT_STARTER" ]; then
  info "Starter $APPS/$DESKTOP_NAME" "Launcher $APPS/$DESKTOP_NAME"
  mkdir -p "$BIN" "$APPS"
  XPP=$(python3 "$QUELLE/einrichten.py" exec "$SYS_DESKTOP")
  sed -e "s|@XPP@|$XPP|" -e "s|@DOCK@|$OPT_DOCK|" "$QUELLE/bin/lernordner-start" > "$BIN/lernordner-start"
  chmod 755 "$BIN/lernordner-start"
  python3 "$QUELLE/einrichten.py" desktop "$SYS_DESKTOP" "$APPS/$DESKTOP_NAME" "$BIN/lernordner-start"
  if command -v update-desktop-database >/dev/null; then update-desktop-database "$APPS" 2>/dev/null || true; fi
fi

# ---- GNOME search: own search provider (runs in addition to the others) ------------------
if [ -n "$OPT_SUCHE" ]; then
  info "Suchanbieter für die GNOME-Suche" "Search provider for GNOME search"
  mkdir -p "$BIN" "$DATA/dbus-1/services"
  sed "s|@BASIS@|$BASIS|" "$QUELLE/bin/lernordner-suche" > "$BIN/lernordner-suche"
  chmod 755 "$BIN/lernordner-suche"
  printf '[D-BUS Service]\nName=de.lernordner.Suche\nExec=%s\n' "$BIN/lernordner-suche" \
    > "$DATA/dbus-1/services/de.lernordner.Suche.service"
  SUCH_INI=$(printf '[Shell Search Provider]\nDesktopId=%s\nBusName=de.lernordner.Suche\nObjectPath=/de/lernordner/Suche\nVersion=2\n' "$DESKTOP_NAME")
  # GNOME Shell reads search providers only from the system data dirs (XDG_DATA_DIRS).
  # First a writable one below $HOME (e.g. Flatpak's), otherwise /usr/local/share via sudo.
  SUCH_ZIEL=""
  IFS=: read -ra DIRS <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
  for d in "${DIRS[@]}"; do
    case "$d" in "$HOME"/*) if [ -d "$d" ] && [ -w "$d" ]; then SUCH_ZIEL="$d/gnome-shell/search-providers"; break; fi;; esac
  done
  if [ -n "$SUCH_ZIEL" ]; then
    mkdir -p "$SUCH_ZIEL"
    printf '%s\n' "$SUCH_INI" > "$SUCH_ZIEL/de.lernordner.Suche.ini"
    echo "  $SUCH_ZIEL/de.lernordner.Suche.ini"
  else
    printf '%s\n' "$SUCH_INI" > "$DATA/de.lernordner.Suche.ini"
    if [ -t 0 ] && command -v sudo >/dev/null && \
       sudo install -D -m 644 "$DATA/de.lernordner.Suche.ini" /usr/local/share/gnome-shell/search-providers/de.lernordner.Suche.ini; then
      echo "  /usr/local/share/gnome-shell/search-providers/de.lernordner.Suche.ini"
    else
      warn "Suchanbieter noch nicht angemeldet. Einmalig ausführen:" "Search provider not registered yet. Run once:"
      echo "  sudo install -D -m 644 '$DATA/de.lernordner.Suche.ini' /usr/local/share/gnome-shell/search-providers/de.lernordner.Suche.ini"
    fi
  fi
  m "  (wirkt nach dem nächsten Anmelden; Test: lernordner-suche --test WORT)" \
    "  (active after the next login; test: lernordner-suche --test WORD)"
fi

# ---- settings ----------------------------------------------------------------------------
info "Einstellungen" "Settings"
mkdir -p "$CFG"
python3 "$QUELLE/einrichten.py" toolbar "$CFG/toolbar.ini"
python3 "$QUELLE/einrichten.py" settings "$CFG/settings.xml" "${SETTINGS_OPT[@]}"

# ---- lgi (needed for the label bar, 📂 Open, colours, background dialogs) -----------------
LUA=$(ldd "$(command -v xournalpp 2>/dev/null || echo /usr/bin/xournalpp)" 2>/dev/null | grep -o 'liblua[0-9.]*' | head -1 | sed 's/liblua//; s/\.$//' || true)
lgi_da() {  # system package or self-built below ~/.local
  local f
  for f in /usr/lib/*/lua/"$LUA"/lgi/corelgilua51.so "$HOME/.local/lib/lua/$LUA/lgi/corelgilua51.so"; do
    [ -f "$f" ] && return 0
  done
  return 1
}
if [ -n "$LUA" ] && lgi_da; then
  m "  lua-lgi für Lua $LUA vorhanden." "  lua-lgi for Lua $LUA found."
else
  warn "lua-lgi für Lua ${LUA:-?} fehlt: ohne lgi gibt es keine Etikett-Leiste, kein 📂 Öffnen und kein Menü Dicke & Farbe (siehe README)." \
       "lua-lgi for Lua ${LUA:-?} is missing: without lgi there is no label bar, no 📂 Open and no thickness & colour menu (see README)."
fi

echo
info "Fertig. Xournal++ starten." "Done. Start Xournal++."
m "Zurück zur normalen Leiste: F10 → Bearbeiten → Werkzeugleisten → Xournal++" \
  "Back to the normal toolbar: F10 → Edit → Toolbars → Xournal++"
m "Deinstallieren: bash uninstall.sh   (Backups: $B)" "Uninstall: bash uninstall.sh   (backups: $B)"
