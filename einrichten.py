#!/usr/bin/env python3
"""Setup helper for Lernordner (called by install.sh).

  einrichten.py settings SETTINGS_XML [--leiste] [--touch] [--autosave] [--marker] [--vollbild] [--stifttaste]
  einrichten.py toolbar  TOOLBAR_INI
  einrichten.py desktop  SYSTEM_DESKTOP TARGET_DESKTOP LAUNCHER
  einrichten.py exec     SYSTEM_DESKTOP          (prints the original program)

Keys taken from the Xournal++ 1.3.3 sources (Settings.cpp, ViewModes.h,
ToolHandler.cpp, ToolbarModel.cpp).
"""
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

LEISTE = "Lernmodus"
# Colours live in LERN_STIFT; chapters/PDF/search in 📂 Open; tags/title/filing in the label bar.
LEISTE_HOCH = "Lernmodus hoch"   # same content, on top instead of left (portrait)
LEISTE_INHALT = ("Plugin::LERN_NEU,Plugin::LERN_OEFFNEN,SEPARATOR,PEN,HIGHLIGHTER,TEXT,ERASER,Plugin::LERN_STIFT,"
                 "SEPARATOR,UNDO,REDO,SPACER,Plugin::LERN_VERWERFEN,Plugin::LERN_DREHEN,TOGGLE_TOUCH_DRAWING")
# No FULLSCREEN button: GNOME 50 loses the pen in fullscreen.
# --stifttaste: second pen button = big eraser (buttonConfig only knows tools, no actions;
# size names veryThin/thin/medium/thick/veryThick, eraserMode "none" = current mode).
STIFTTASTEN = {
    "stylus2": {"tool": "eraser", "size": "veryThick", "eraserMode": "none"},
}

GRUPPEN = {
    # study toolbar; normal window like a fullscreen: toolbar only, no menu, no sidebar, maximised.
    # Real fullscreen is avoided on purpose (GNOME 50 loses the pen there). Lines a bit thicker.
    "--leiste": {"selectedToolbar": LEISTE, "defaultViewModeAttributes": "showToolbar",
                 "menubarVisible": "false", "showSidebar": "false", "maximized": "true",
                 "pressureMultiplier": "1.2"},
    # fullscreen (F11) without menu and sidebar ("goFullscren" sic!)
    "--vollbild": {"fullscreenViewModeAttributes": "goFullscren,showToolbar"},
    # touchscreen only scrolls/zooms, does not draw
    "--touch": {"touchDrawing": "false", "zoomGesturesEnabled": "true"},
    "--autosave": {"autosaveEnabled": "true", "autosaveTimeout": "2"},
}


def settings(pfad, optionen):
    p = Path(pfad)
    if p.exists():
        parser = ET.XMLParser(target=ET.TreeBuilder(insert_comments=True))
        baum = ET.parse(p, parser)
        wurzel = baum.getroot()
        if wurzel.tag != "settings":
            sys.exit(f"{p}: unexpected format (root {wurzel.tag})")
    else:
        wurzel = ET.Element("settings")
        baum = ET.ElementTree(wurzel)

    def property(name, wert):
        for e in wurzel.findall("property"):
            if e.get("name") == name:
                e.set("value", wert)
                return
        ET.SubElement(wurzel, "property", {"name": name, "value": wert})

    for opt in optionen:
        for k, v in GRUPPEN.get(opt, {}).items():
            property(k, v)

    # never leave the plugin disabled
    for e in wurzel.findall("property"):
        if e.get("name") == "pluginDisabled":
            teile = [t for t in e.get("value", "").split(",") if t and Path(t).name != "Lernordner"]
            e.set("value", ",".join(teile))

    def data(eltern, name):
        for e in eltern.findall("data"):
            if e.get("name") == name:
                return e
        return ET.SubElement(eltern, "data", {"name": name})

    def attribut(eltern, name, typ, wert, nur_wenn_fehlt=False):
        for e in eltern.findall("attribute"):
            if e.get("name") == name:
                if not nur_wenn_fehlt:
                    e.set("type", typ)
                    e.set("value", wert)
                return
        ET.SubElement(eltern, "attribute", {"name": name, "type": typ, "value": wert})

    if "--marker" in optionen:
        tools = data(wurzel, "tools")
        attribut(tools, "current", "string", "pen", nur_wenn_fehlt=True)  # otherwise "tools" is ignored
        marker = data(tools, "highlighter")
        attribut(marker, "color", "hex", "ffffff00")       # yellow (ARGB), no fill -> translucent
        attribut(marker, "fill", "int", "0")
        attribut(marker, "drawingType", "string", "default")
        attribut(marker, "size", "string", "MEDIUM", nur_wenn_fehlt=True)

    # pen buttons (Settings.cpp, loadButtonConfig); other entries stay untouched
    if "--stifttaste" in optionen:
        tasten = data(wurzel, "buttonConfig")
        for taste, werte in STIFTTASTEN.items():
            eintrag = data(tasten, taste)
            for name, wert in werte.items():
                attribut(eintrag, name, "string", wert)

    ET.indent(baum, space="  ")
    baum.write(p, encoding="UTF-8", xml_declaration=True)
    ET.parse(p)  # double check


def toolbar(pfad):
    p = Path(pfad)
    alt = p.read_text(encoding="utf-8") if p.exists() else ""
    zeilen, ueberspringen = [], False
    for z in alt.splitlines():
        kopf = re.match(r"\s*\[(.*)\]\s*$", z)
        if kopf:
            ueberspringen = kopf.group(1) in (LEISTE, LEISTE_HOCH)
        if not ueberspringen:
            zeilen.append(z)
    while zeilen and not zeilen[-1].strip():
        zeilen.pop()
    if zeilen:
        zeilen.append("")
    zeilen += [f"[{LEISTE}]", f"name={LEISTE}", f"toolbarLeft1={LEISTE_INHALT}", "",
               f"[{LEISTE_HOCH}]", f"name={LEISTE_HOCH}", f"toolbarTop1={LEISTE_INHALT}", ""]
    p.write_text("\n".join(zeilen), encoding="utf-8")


def startprogramm(system_desktop):
    try:
        for z in Path(system_desktop).read_text(encoding="utf-8").splitlines():
            if z.startswith("Exec="):
                return z[5:].split()[0]
    except OSError:
        pass
    return "xournalpp"


def desktop(system_desktop, ziel, starter):
    text = Path(system_desktop).read_text(encoding="utf-8")
    neu = re.sub(r"^Exec=.*$", f"Exec={starter} %f", text, flags=re.M)
    if "MimeType=" not in neu:
        sys.exit("system launcher without MimeType – aborting")
    Path(ziel).write_text(neu, encoding="utf-8")


if __name__ == "__main__":
    befehl, args = sys.argv[1], sys.argv[2:]
    if befehl == "settings":
        settings(args[0], args[1:])
    elif befehl == "toolbar":
        toolbar(args[0])
    elif befehl == "exec":
        print(startprogramm(args[0]))
    elif befehl == "desktop":
        desktop(*args)
    else:
        sys.exit(__doc__)
