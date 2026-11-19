#!/bin/bash
# Ablauf-Tests mit echtem GTK 3 (Widgets werden nur gebaut, nicht gezeigt),
# Attrappe der app-API, Ersatz-zenity und einem Wegwerf-Basisordner.
# Aufruf: bash tests/lauf.sh   (braucht lua5.4 + lgi unter ~/.local, eine Sitzung mit Display)
set -e
cd "$(dirname "$0")/.."
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/basis/00 Eingang" "$T/basis/03 Chronische Erkrankungen" "$T/basis/10 Prüfungsprotokolle" "$T/basis/99 Archiv"
printf '#!/bin/sh\necho "zenity $*" >&2\n' > "$T/bin/zenity"; chmod +x "$T/bin/zenity"
cp plugin/Lernordner/template.xopp "$T/basis/00 Eingang/2026-11-07 22-18.xopp"
# öffentliche Version: Pfade aus einer eigenen lernordner.ini, Sprache Deutsch
printf '[lernordner]\nbasis = %s\neingang = 00 Eingang\npapierkorb = .papierkorb\nkapitelliste = %s\npdf_ordner = \n' \
  "$T/basis" "$PWD/examples/kapitel-allgemeinmedizin-chenot-scherer-2.tsv" > "$T/lernordner.ini"
export LERNORDNER_CONFIG="$T/lernordner.ini" LERNORDNER_LANG=de
export LERNORDNER_BASIS="$T/basis" PATH="$T/bin:$PATH" XDG_STATE_HOME="$T/state"
python3 plugin/Lernordner/lernordner.py kapitel-titel "03 Chronische Erkrankungen" "diabetes mellitus" >/dev/null
echo "== Öffnen / Neues Kapitel";  lua5.4 tests/test_oeffnen.lua plugin/Lernordner/main.lua
echo "== Etikett-Leiste";          lua5.4 tests/test_etikett.lua plugin/Lernordner/main.lua
echo "== Dateien"; (cd "$T/basis" && find . -name '*.xopp' | sort)
