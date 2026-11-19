#!/usr/bin/env python3
"""
lerntags – finds #tags in Xournal++ (.xopp) and Rnote (.rnote) notes.
           findet #Tags in Xournal++- (.xopp) und Rnote-Notizen (.rnote).

Tags are typed text in a note (text tool), e.g. "#cardio #wdh".
Tags in file names are recognised as well.

Usage:
  lerntags              choose tag, then note, and open it
  lerntags cardio       show notes tagged #cardio
  lerntags -l           list all tags with counts (terminal)
  lerntags -t cardio    list files tagged #cardio (terminal)
  lerntags --waehle [tag]
                        same dialogs, but only print the chosen path (used by the plugin)

Chapter tags (#k063) are shown with their title from the chapter list.
Folder and chapter list come from ~/.config/xournalpp/lernordner.ini
(override: LERNTAGS_DIR, LERNTAGS_KAPITEL).
"""

import configparser
import gzip
import json
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path

TAG_RE = re.compile(r"#([^\W\d_][\w-]*)")  # starts with a letter, umlauts ok
KTAG_RE = re.compile(r"k(\d{3})$")


def sprache():
    for var in ("LERNORDNER_LANG", "LC_ALL", "LC_MESSAGES", "LANG", "LANGUAGE"):
        v = os.environ.get(var)
        if v:
            return "de" if v.lower().startswith("de") else "en"
    return "en"


DE = sprache() == "de"


def t(de, en):
    return de if DE else en


def konfig():
    xdg = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    pfad = Path(os.environ.get("LERNORDNER_CONFIG") or xdg / "xournalpp" / "lernordner.ini")
    cp = configparser.ConfigParser(interpolation=None)
    cp.read(pfad, encoding="utf-8")
    return cp["lernordner"] if cp.has_section("lernordner") else {}


def lies(pfad):
    """File content, gzip-compressed or plain (fresh templates)."""
    with open(pfad, "rb") as f:
        roh = f.read()
    return gzip.decompress(roh) if roh[:2] == b"\x1f\x8b" else roh


def kapiteltitel(pfad):
    """{'063': 'Diabetes mellitus', …} from the chapter list (empty if missing)."""
    titel = {}
    try:
        with open(Path(pfad).expanduser(), encoding="utf-8") as f:
            for z in f:
                teile = z.rstrip("\n").split("\t")
                if len(teile) >= 3 and teile[0].strip().isdigit():
                    titel[f"{int(teile[0]):03d}"] = teile[2].strip()
    except (OSError, TypeError):
        pass
    return titel


def anzeige(tag, titel):
    m = KTAG_RE.match(tag)
    if m and m.group(1) in titel:
        return f"#{tag} {titel[m.group(1)]}"
    return f"#{tag}"


def sortierschluessel(tag):
    """Free tags alphabetically, then chapter tags by number."""
    m = KTAG_RE.match(tag)
    return (1, int(m.group(1)), tag) if m else (0, 0, tag)


def texte_rnote(pfad):
    daten = json.loads(lies(pfad))
    gefunden = []

    def laufe(obj):
        if isinstance(obj, dict):
            for k, v in obj.items():
                if k == "text" and isinstance(v, str):
                    gefunden.append(v)
                else:
                    laufe(v)
        elif isinstance(obj, list):
            for v in obj:
                laufe(v)

    laufe(daten)
    return gefunden


def texte_xopp(pfad):
    wurzel = ET.fromstring(lies(pfad))
    return [el.text for el in wurzel.iter("text") if el.text]


def sammle(ordner):
    """{tag: set(files)}"""
    tags = defaultdict(set)
    for pfad in Path(ordner).rglob("*"):
        endung = pfad.suffix.lower()
        if endung not in (".rnote", ".xopp") or not pfad.is_file():
            continue
        teile = pfad.relative_to(ordner).parts          # skip hidden files/folders and autosaves
        if any(x.startswith(".") for x in teile) or ".autosave" in pfad.name:
            continue
        texte = [pfad.stem]
        try:
            texte += texte_rnote(pfad) if endung == ".rnote" else texte_xopp(pfad)
        except Exception as e:  # damaged/unknown file
            print(t("Übersprungen", "Skipped") + f": {pfad} ({e})", file=sys.stderr)
        for x in texte:
            for tag in TAG_RE.findall(x):
                tags[tag.lower()].add(pfad)
    return tags


def oeffne(pfad):
    subprocess.Popen(["xdg-open", str(pfad)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def zenity(*args):
    r = subprocess.run(["zenity", *args], capture_output=True, text=True, encoding="utf-8")
    return r.stdout.strip() if r.returncode == 0 else None


def waehle_datei(ordner, dateien, tag, titel, nur_ausgeben=False):
    dateien = sorted(dateien, key=lambda p: str(p).lower())
    zeilen = []
    for p in dateien:
        zeilen += [p.stem, str(p.parent.relative_to(ordner)), str(p)]
    kopf = anzeige(tag, titel)
    wahl = zenity("--list", f"--title={kopf}", "--width=700", "--height=600",
                  "--text=" + t(f"{len(dateien)} Notiz(en) mit {kopf}", f"{len(dateien)} note(s) with {kopf}"),
                  "--column=" + t("Notiz", "Note"), "--column=" + t("Ordner", "Folder"),
                  "--column=Path", "--hide-column=3", "--print-column=3",
                  *([] if nur_ausgeben else ["--multiple"]), "--separator=\n", *zeilen)
    pfade = [p for p in (wahl or "").splitlines() if p]
    if nur_ausgeben:
        if not pfade:
            sys.exit(1)
        print(pfade[0])
        return
    for p in pfade:
        oeffne(p)


def main():
    k = konfig()
    ordner = Path(os.environ.get("LERNTAGS_DIR") or k.get("basis") or "~/Documents").expanduser()
    if not ordner.is_dir():
        sys.exit(t("Ordner nicht gefunden: ", "Folder not found: ") + str(ordner))
    titel = kapiteltitel(os.environ.get("LERNTAGS_KAPITEL") or k.get("kapitelliste") or "")

    args = sys.argv[1:]
    nur_ausgeben = args[:1] == ["--waehle"]
    if nur_ausgeben:
        args = args[1:]
    if args[:1] in (["-h"], ["--help"]):
        print(__doc__)
        return
    tags = sammle(ordner)

    if args[:1] == ["-l"]:
        frei = sorted((x for x in tags if not KTAG_RE.match(x)), key=lambda x: (-len(tags[x]), x))
        kap = sorted((x for x in tags if KTAG_RE.match(x)), key=sortierschluessel)
        for tag in frei + kap:
            print(f"{len(tags[tag]):3}  {anzeige(tag, titel)}")
        return

    if args[:1] == ["-t"] and len(args) > 1:
        tag = args[1].lstrip("#").lower()
        for p in sorted(tags.get(tag, [])):
            print(p)
        return

    if not shutil.which("zenity"):
        sys.exit(t("zenity fehlt: sudo apt install zenity", "zenity is missing: sudo apt install zenity"))

    if args:
        tag = args[0].lstrip("#").lower()
    else:
        if not tags:
            zenity("--info", "--text=" + t("Noch keine #Tags gefunden.", "No #tags found yet."))
            sys.exit(1 if nur_ausgeben else 0)
        zeilen = []
        for x in sorted(tags, key=sortierschluessel):
            zeilen += [anzeige(x, titel), str(len(tags[x])), x]
        wahl = zenity("--list", "--title=" + t("Lern-Tags", "Study tags"), "--width=520", "--height=700",
                      "--text=" + t("Tag wählen:", "Choose tag:"), "--column=Tag",
                      "--column=" + t("Notizen", "Notes"), "--column=key", "--hide-column=3",
                      "--print-column=3", *zeilen)
        if not wahl:
            sys.exit(1 if nur_ausgeben else 0)
        tag = wahl.split("|")[0].lstrip("#")

    if tag not in tags:
        zenity("--info", "--text=" + t(f"Keine Notizen mit {anzeige(tag, titel)} gefunden.",
                                      f"No notes with {anzeige(tag, titel)} found."))
        sys.exit(1 if nur_ausgeben else 0)
    waehle_datei(ordner, tags[tag], tag, titel, nur_ausgeben)


if __name__ == "__main__":
    main()
