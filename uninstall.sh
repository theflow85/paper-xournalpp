#!/usr/bin/env bash
# Removes Lernordner and restores the backups from before the first installation.
# Your notes and their folders are not touched.
set -euo pipefail

CFG="${XDG_CONFIG_HOME:-$HOME/.config}/xournalpp"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
PLUGIN="$CFG/plugins/Lernordner"
BIN="$HOME/.local/bin"
APPS="$DATA/applications"
ICONS="$DATA/icons/hicolor/scalable/actions"
BACKUPS="$CFG/lernordner-backups"
ERSTE="$BACKUPS/before-first-install"
JETZT="$BACKUPS/before-uninstall-$(date +%Y-%m-%d_%H-%M-%S)"

case "${LERNORDNER_LANG:-${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}}" in de*) DE=1 ;; *) DE= ;; esac
m()    { if [ -n "$DE" ]; then printf '%s\n' "$1"; else printf '%s\n' "$2"; fi; }
fail() { printf '\033[31m%s\033[0m %s\n' "$(m Fehler: Error:)" "$(m "$1" "$2")" >&2; exit 1; }

if pgrep -x xournalpp >/dev/null 2>&1 || pgrep -x xournalpp-wrapper >/dev/null 2>&1; then
  fail "Xournal++ läuft noch. Bitte schließen und erneut starten." "Xournal++ is still running. Please close it and run again."
fi
[ -d "$ERSTE" ] || fail "Kein Backup gefunden: $ERSTE" "No backup found: $ERSTE"
DESKTOP_NAME=$(cat "$ERSTE/desktop-name" 2>/dev/null || echo com.github.xournalpp.xournalpp.desktop)

mkdir -p "$JETZT"
for f in "$CFG/settings.xml" "$CFG/toolbar.ini" "$APPS/$DESKTOP_NAME"; do
  if [ -e "$f" ]; then cp -a "$f" "$JETZT/"; fi
done

zurueck() {  # short-name target
  if [ -e "$ERSTE/$1" ]; then
    cp -a "$ERSTE/$1" "$2"; m "zurückgespielt: $2" "restored: $2"
  elif [ -e "$ERSTE/$1.missing" ]; then
    rm -f "$2"; m "entfernt (gab es vorher nicht): $2" "removed (did not exist before): $2"
  fi
}
zurueck settings.xml "$CFG/settings.xml"
zurueck toolbar.ini  "$CFG/toolbar.ini"
zurueck desktop      "$APPS/$DESKTOP_NAME"
mv "$ERSTE" "$BACKUPS/restored-$(date +%Y-%m-%d_%H-%M-%S)"

if [ -L "$BIN/lerntags" ] && [ "$(readlink "$BIN/lerntags")" = "$PLUGIN/lerntags.py" ]; then rm -f "$BIN/lerntags"; fi
rm -rf "${PLUGIN:?}"
rm -f "$BIN/lernordner-start" "$ICONS"/lernordner-*.svg
rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/lernordner/drehen"
# search provider (GNOME search)
rm -f "$BIN/lernordner-suche" "$DATA/dbus-1/services/de.lernordner.Suche.service" "$DATA/de.lernordner.Suche.ini"
IFS=: read -ra DIRS <<< "${XDG_DATA_DIRS:-}"
for d in "${DIRS[@]}"; do
  case "$d" in "$HOME"/*) rm -f "$d/gnome-shell/search-providers/de.lernordner.Suche.ini";; esac
done
if [ -e /usr/local/share/gnome-shell/search-providers/de.lernordner.Suche.ini ]; then
  m "Zusätzlich entfernen: sudo rm /usr/local/share/gnome-shell/search-providers/de.lernordner.Suche.ini" \
    "Also remove: sudo rm /usr/local/share/gnome-shell/search-providers/de.lernordner.Suche.ini"
fi
if command -v update-desktop-database >/dev/null; then update-desktop-database "$APPS" 2>/dev/null || true; fi

m "Lernordner entfernt. Notizen und lernordner.ini bleiben erhalten." "Lernordner removed. Notes and lernordner.ini are kept."
