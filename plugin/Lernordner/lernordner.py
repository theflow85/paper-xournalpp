#!/usr/bin/env python3
"""
Lernordner – helper for the Xournal++ plugin of the same name.
Hilfsprogramm für das gleichnamige Xournal++-Plugin.

Does everything outside Xournal++: zenity dialogs, creating/copying/verifying
files, generating .xopp files for PDFs, trash. The Lua plugin calls it and reads
lines of the form  KEY<TAB>value.

Configuration: ~/.config/xournalpp/lernordner.ini (created on first use).

Commands: kapitel | neu | neu-eingang | pdf [--ziel FOLDER] [PDF ...] | tags
  titel [SUGGESTION] | ordner [--titel T] [--vorauswahl NAME] | suche
  ist-kapitel FILE | zielname SRC FOLDER [TITLE] | signatur FILE | warte FILE SIG
  kopiere SRC DST | papierkorb FILE ... | ist-vorlage FILE | seiten FILE
  aufraeumen [--zeigen] | meldung KEY|TEXT | fehler KEY|TEXT | startziel [FILE] | leiste [--test] | drehen [an|aus|umschalten] | verwerfen FILE | sprache
  init [BASE_FOLDER] | konfig
  ablage [FOLDER] | kapitel-neu PART NO | kapitel-titel PART TITLE | kapitel-frei
  zielname-stamm SRC FOLDER STEM | ordner-neu NAME [--in FOLDER] | ziel-name SRC FOLDER [TITLE] | tags-liste
"""

import configparser
import datetime as dt
import filecmp
import gzip
import html
import os
import re
import shutil
import subprocess
import sys
import time
import unicodedata
from pathlib import Path

PLUGIN_DIR = Path(__file__).resolve().parent
VORLAGE = PLUGIN_DIR / "template.xopp"
LERNTAGS = PLUGIN_DIR / "lerntags.py"
XDG_CONFIG = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
KONFIG = Path(os.environ.get("LERNORDNER_CONFIG") or XDG_CONFIG / "xournalpp" / "lernordner.ini")

# Text styles – must match main.lua (used to recognise title and tag line)
TITEL_GROESSE, TITEL_FARBE = 22, 0x1A1A1A
TAG_GROESSE, TAG_FARBE = 10, 0x808080
TITEL_POS = (80, 22)                            # lined page (header area)
# Tags live invisibly above the page (y < 0: not drawn or exported, lerntags still finds
# them); the label bar shows them (must match main.lua)
TAG_POS = (0, -40)
# last used note (written by main.lua; the launcher opens it again)
ZULETZT = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "lernordner" / "zuletzt"
DREHEN = ZULETZT.with_name("drehen")      # "an"/"aus": toolbar (and dock) follow the screen rotation

LISTE = ["--width=640", "--height=820"]
TAG_RE = re.compile(r"^[^\W\d_][\w-]*$")
VERBOTEN = re.compile(r'[/\\:*?"<>|\x00-\x1f\x7f]')


# ---- Language / Sprache ---------------------------------------------------------
def _sprache():
    for var in ("LERNORDNER_LANG", "LC_ALL", "LC_MESSAGES", "LANG", "LANGUAGE"):
        v = os.environ.get(var)
        if v:
            return "de" if v.lower().startswith("de") else "en"
    return "en"


SPRACHE = _sprache()

TEXTE = {
    "eingang": ("00 Eingang", "00 Inbox"),
    "papierkorb": (".papierkorb", ".trash"),
    "verwerfen_ok": ("Verwerfen", "Discard"),
    "verwerfen_nein": ("Behalten", "Keep"),
    "verwerfen_text": ("Notiz „{name}“ verwerfen?\n\nSie kommt in den Papierkorb ({korb}) und kann dort wieder herausgeholt werden.",
                       "Discard the note “{name}”?\n\nIt goes to the trash folder ({korb}) and can be taken out again."),
    "basis": ("Lernordner", "Study notes"),
    "neuer_ordner": ("➕ Neuer Ordner…", "➕ New folder…"),
    "neuer_ordner_titel": ("Neuer Ordner", "New folder"),
    "neuer_ordner_text": ("Name des neuen Ordners:", "Name of the new folder:"),
    "ordner": ("Ordner", "Folder"),
    "ordner_waehlen": ("Ordner wählen", "Choose folder"),
    "neue_notiz": ("Neue Notiz – Ordner", "New note – folder"),
    "pdf_ablegen": ("PDF ablegen in", "Put PDF into"),
    "pdf_waehlen": ("PDF(s) wählen", "Choose PDF(s)"),
    "alle_dateien": ("Alle Dateien", "All files"),
    "kapitel": ("Kapitel", "Chapter"),
    "kap_kurz": ("Kap.", "Ch."),
    "teil": ("Teil", "Part"),
    "teil_waehlen": ("Teil wählen:", "Choose part:"),
    "kapitel_waehlen": ("Kapitel wählen:", "Choose chapter:"),
    "kapitel_ankreuzen": ("Kapitel ankreuzen (mehrere möglich):", "Tick chapters (several allowed):"),
    "kapitel_zuordnen": ("Kapitel zuordnen", "Assign chapter"),
    "nr": ("Nr", "No"),
    "titel": ("Titel", "Title"),
    "notiz": ("Notiz", "Note"),
    "tags": ("Tags", "Tags"),
    "tags_ankreuzen": ("Tags ankreuzen:", "Tick tags:"),
    "tag": ("Tag", "Tag"),
    "wdh": ("wiederholen", "review"),
    "ok": ("sitzt", "known"),
    "kap_zuordnen_eintrag": ("📖 Kapitel zuordnen…", "📖 Assign chapter…"),
    "neuer_tag_eintrag": ("➕ Neuer Tag…", "➕ New tag…"),
    "neuer_tag": ("Neuer Tag", "New tag"),
    "neue_tags_text": ("Neue Tags (mehrere mit Leerzeichen):", "New tags (separate with spaces):"),
    "tags_ignoriert": ("Ignoriert (Tags müssen mit einem Buchstaben beginnen):\n",
                       "Ignored (tags must start with a letter):\n"),
    "titel_text": ("Titel der Notiz:", "Title of the note:"),
    "keine_kapitelliste": (
        "Es ist noch keine Kapitelliste eingerichtet.\n\nLege eine Datei an:\n{pfad}\n\n"
        "Format (Tabulator-getrennt): Nummer, Ordner, Titel – siehe examples/ im Paket.",
        "No chapter list set up yet.\n\nCreate this file:\n{pfad}\n\n"
        "Format (tab-separated): number, folder, title – see examples/ in the package."),
    "nicht_importiert": ("Nicht importiert:\n\n", "Not imported:\n\n"),
    "unerwartet": ("Unerwarteter Fehler ({cmd}):\n{err}\n\nNichts wurde verschoben.",
                   "Unexpected error ({cmd}):\n{err}\n\nNothing was moved."),
    # messages used by main.lua
    "m_speichern_fehlgeschlagen": (
        "Die aktuelle Notiz konnte nicht gespeichert werden.\nEs wurde nichts geöffnet.",
        "The current note could not be saved.\nNothing was opened."),
    "m_kein_pfad_tags": (
        "Tags gesetzt. Diese Notiz hat noch keinen Speicherort – bitte über „Neu“ oder „PDF“ arbeiten.",
        "Tags added. This note has no file yet – please start notes via “New” or “PDF”."),
    "m_kein_pfad_ablegen": ("Diese Notiz hat noch keinen Speicherort und kann nicht abgelegt werden.",
                            "This note has no file yet and cannot be filed."),
    "m_kapitel_bleibt": ("Kapitel-Notizen bleiben in ihrem Ordner.",
                         "Chapter notes stay in their folder."),
    "m_ablegen_abgebrochen": ("Speichern wurde nicht bestätigt – Ablegen abgebrochen.\nDie Notiz bleibt, wo sie ist.",
                              "Saving was not confirmed – filing cancelled.\nThe note stays where it is."),
    "m_liegt_schon": ("Gespeichert. Die Notiz liegt bereits unter diesem Namen dort.",
                      "Saved. The note is already there under this name."),
    "m_kopie_nicht_offen": ("Die Kopie wurde angelegt, ließ sich aber nicht öffnen.\nDas Original bleibt erhalten.",
                            "The copy was created but could not be opened.\nThe original is kept."),
    # errors
    "e_zenity": ("zenity fehlt: sudo apt install zenity", "zenity is missing: sudo apt install zenity"),
    "e_basis": ("Basisordner fehlt: {p}", "Base folder missing: {p}"),
    "e_kein_name": ("Kein freier Dateiname für {n}", "No free file name for {n}"),
    "e_ordner": ("Ordner nicht gefunden: {p}", "Folder not found: {p}"),
    "e_pruefung": ("Prüfung fehlgeschlagen: {p}", "Verification failed: {p}"),
    "e_xopp": ("Keine gültige Xournal++-Datei: {p}", "Not a valid Xournal++ file: {p}"),
    "e_vorlage": ("Vorlage ohne <layer>", "Template without <layer>"),
    "e_pdfinfo": ("pdfinfo kann die Datei nicht lesen:\n{n}\n{e}", "pdfinfo cannot read the file:\n{n}\n{e}"),
    "e_seitengroesse": ("Seitengröße von Seite {i} unbekannt: {n}", "Unknown size of page {i}: {n}"),
    "e_nicht_gefunden": ("Datei nicht gefunden: {p}", "File not found: {p}"),
    "e_kopie": ("Kopie fehlerhaft: {p}", "Copy is corrupt: {p}"),
    "e_seitenzahl": ("Seitenzahl stimmt nicht: {p}", "Page count mismatch: {p}"),
    "e_ziel_existiert": ("Ziel existiert schon: {p}", "Target already exists: {p}"),
    "e_unvollstaendig": ("Die gespeicherte Notiz ist unvollständig – Abbruch.",
                         "The saved note is incomplete – cancelled."),
    "e_hintergrund": ("Hintergrund-Datei nicht gefunden:\n{p}", "Background file not found:\n{p}"),
    "e_bild_konflikt": ("Im Zielordner liegt schon eine andere Datei {p}",
                        "The target folder already contains a different file {p}"),
    "e_kopie_anders": ("Kopie stimmt nicht mit dem Original überein: {n}", "Copy differs from the original: {n}"),
    "e_kopie_xml": ("Kopie der Notiz stimmt nicht mit dem Erwarteten überein.",
                    "Copy of the note does not match what was expected."),
    "e_kopie_pdf": ("Die Kopie findet ihr PDF nicht.", "The copy cannot find its PDF."),
    "e_speichern_zeit": ("Speichern wurde nicht innerhalb von {s:g} s bestätigt.",
                         "Saving was not confirmed within {s:g} s."),
    "e_lerntags": ("lerntags nicht gefunden: {p}", "lerntags not found: {p}"),
    "e_name_leer": ("Der Name darf nicht leer sein.", "The name must not be empty."),
    "e_ordnername": ("Bitte einen gültigen Ordnernamen eingeben.", "Please enter a valid folder name."),
    "e_keine_nummer": ("Keine freie Nummer mehr.", "No free number left."),
    "e_kapitel_da": ("Das Kapitel „{t}“ gibt es in diesem Ordner schon.", "The chapter “{t}” already exists in this folder."),
    "e_eine_ebene": ("Unterordner gibt es nur eine Ebene tief.", "Subfolders are only one level deep."),
    "e_titel_leer": ("Bitte einen Titel für das Kapitel eingeben.", "Please enter a title for the chapter."),
    "m_speichern_unbestaetigt": ("Speichern wurde nicht bestätigt – nichts verschoben.\nDie Notiz bleibt, wo sie ist.",
                                 "Saving was not confirmed – nothing was moved.\nThe note stays where it is."),
}


def _(schluessel, **kw):
    de, en = TEXTE[schluessel]
    text = de if SPRACHE == "de" else en
    return text.format(**kw) if kw else text


# ---- Configuration --------------------------------------------------------------
def dokumente():
    try:
        r = subprocess.run(["xdg-user-dir", "DOCUMENTS"], capture_output=True, text=True)
        p = r.stdout.strip()
        if r.returncode == 0 and p and p != str(Path.home()):
            return Path(p)
    except FileNotFoundError:
        pass
    for n in ("Dokumente", "Documents"):
        if (Path.home() / n).is_dir():
            return Path.home() / n
    return Path.home()


class Konfig:
    def __init__(self):
        self.cp = configparser.ConfigParser(interpolation=None)
        neu = not KONFIG.exists()
        if not neu:
            self.cp.read(KONFIG, encoding="utf-8")
        if not self.cp.has_section("lernordner"):
            self.cp.add_section("lernordner")
        s = self.cp["lernordner"]
        s.setdefault("basis", str(dokumente() / _("basis")))
        s.setdefault("eingang", _("eingang"))
        s.setdefault("papierkorb", _("papierkorb"))
        s.setdefault("kapitelliste", str(KONFIG.parent / "lernordner-kapitel.tsv"))
        s.setdefault("pdf_ordner", "")
        if neu:
            self.speichern()

    def __getitem__(self, k):
        return self.cp["lernordner"][k]

    def setze(self, k, v):
        self.cp["lernordner"][k] = v
        self.speichern()

    def speichern(self):
        KONFIG.parent.mkdir(parents=True, exist_ok=True)
        tmp = KONFIG.with_suffix(".tmp")
        with open(tmp, "w", encoding="utf-8") as f:
            self.cp.write(f)
        os.replace(tmp, KONFIG)


K = None


def konfig():
    global K
    if K is None:
        K = Konfig()
    return K


def basis():
    p = Path(konfig()["basis"]).expanduser()
    p.mkdir(parents=True, exist_ok=True)
    return p


def eingang():
    p = basis() / konfig()["eingang"]
    p.mkdir(parents=True, exist_ok=True)
    return p


def kapitelliste():
    return Path(konfig()["kapitelliste"]).expanduser()


class Abbruch(Exception):
    """Error reported to the user; nothing was changed."""


# ---- Output for Lua --------------------------------------------------------------
def aus(schluessel, *werte):
    print("\t".join([schluessel, *[str(w) for w in werte]]), flush=True)


# ---- zenity -------------------------------------------------------------------------
def zenity(*args):
    """stdout, or None if cancelled/closed."""
    try:
        r = subprocess.run(["zenity", *args], capture_output=True, text=True,
                           encoding="utf-8", errors="replace")
    except FileNotFoundError:
        raise Abbruch(_("e_zenity"))
    if r.returncode != 0:
        return None
    return r.stdout.rstrip("\n")


def meldung(text, fehler=False):
    try:
        subprocess.run(["zenity", "--error" if fehler else "--info", "--no-markup",
                        "--title=Lernordner", "--width=420", f"--text={text}"],
                       capture_output=True)
    except FileNotFoundError:
        print(text, file=sys.stderr)


# ---- Helpers -----------------------------------------------------------------------
def heute():
    return dt.date.today().isoformat()


def saubere_name(s, maxlen=None):
    s = unicodedata.normalize("NFC", s)
    s = re.sub(r"\s*[/\\|]\s*", "-", s)          # "Diagnosis/Therapy" -> "Diagnosis-Therapy"
    s = VERBOTEN.sub("", s)
    s = re.sub(r"\s+", " ", s).strip(" .")
    if maxlen and len(s) > maxlen:
        s = s[:maxlen].rstrip(" .-–,;")
    return s


def eindeutig(pfad: Path) -> Path:
    """pfad, or 'Name (2).ext', 'Name (3).ext' … if taken."""
    if not pfad.exists():
        return pfad
    for i in range(2, 1000):
        p = pfad.with_name(f"{pfad.stem} ({i}){pfad.suffix}")
        if not p.exists():
            return p
    raise Abbruch(_("e_kein_name", n=pfad.name))


def ordner_liste():
    """Sub-folders of the base folder, sorted, without hidden ones."""
    b = basis()
    return sorted((p for p in b.iterdir() if p.is_dir() and not p.name.startswith(".")),
                  key=lambda p: p.name.lower())


def lade_kapitel():
    """[(number, folder, title)] or [] if no chapter list exists."""
    pfad = kapitelliste()
    if not pfad.is_file():
        return []
    kap = []
    with open(pfad, encoding="utf-8") as f:
        for z in f:
            z = z.rstrip("\n")
            if not z.strip() or z.startswith("#"):
                continue
            teile = z.split("\t", 2)
            if len(teile) == 3 and teile[0].strip().isdigit():
                kap.append((int(teile[0]), saubere_name(teile[1]) or "Kapitel", teile[2].strip()))
    return kap


def lies_xml(pfad: Path) -> bytes:
    daten = Path(pfad).read_bytes()
    if daten[:2] == b"\x1f\x8b":
        return gzip.decompress(daten)
    return daten


def zaehle_seiten(pfad: Path) -> int:
    return max(1, len(re.findall(rb"<page\b", lies_xml(pfad))))


def text_xml(text, groesse, farbe, x, y):
    return (f'<text font="Sans" size="{groesse}" x="{x}" y="{y}" color="#{farbe:06x}ff">'
            f'{html.escape(text, quote=False)}</text>')


def vorlage_mit_texten(texte) -> bytes:
    xml = VORLAGE.read_text(encoding="utf-8")
    inhalt = "\n".join(text_xml(*t) for t in texte)
    m = re.search(r"<layer\s*/>", xml)
    if m:
        xml = xml[:m.start()] + f"<layer>\n{inhalt}\n</layer>" + xml[m.end():]
    else:
        m = re.search(r"<layer\b[^>]*>", xml)
        if not m:
            raise Abbruch(_("e_vorlage"))
        xml = xml[:m.end()] + "\n" + inhalt + xml[m.end():]
    return xml.encode("utf-8")


def schreibe_neu(pfad: Path, daten: bytes, komprimiert=True):
    """Writes a NEW file (never overwrites) and verifies it."""
    roh = gzip.compress(daten, mtime=0) if komprimiert else daten
    with open(pfad, "xb") as f:
        f.write(roh)
        f.flush()
        os.fsync(f.fileno())
    if pfad.read_bytes() != roh:
        raise Abbruch(_("e_pruefung", p=pfad))


def pruefe_xopp(pfad: Path):
    import xml.etree.ElementTree as ET
    wurzel = ET.fromstring(lies_xml(pfad))
    if wurzel.tag != "xournal" or not wurzel.findall("page"):
        raise Abbruch(_("e_xopp", p=pfad))
    return wurzel


# ---- Selection dialogs -------------------------------------------------------------
def waehle_ordner(titel=None, vorauswahl=None):
    titel = titel or _("ordner_waehlen")
    namen = [p.name for p in ordner_liste()] + [_("neuer_ordner")]
    if vorauswahl and vorauswahl in namen:
        zeilen = []
        for n in namen:
            zeilen += ["TRUE" if n == vorauswahl else "FALSE", n]
        wahl = zenity("--list", "--radiolist", f"--title={titel}", f"--text={_('ordner')}:",
                      *LISTE, "--column=", f"--column={_('ordner')}", *zeilen)
    else:
        wahl = zenity("--list", f"--title={titel}", f"--text={_('ordner')}:", *LISTE,
                      f"--column={_('ordner')}", *namen)
    if not wahl:
        return None
    wahl = wahl.split("|")[0]
    if wahl == _("neuer_ordner"):
        name = zenity("--entry", f"--title={_('neuer_ordner_titel')}", "--width=420",
                      f"--text={_('neuer_ordner_text')}")
        name = saubere_name(name or "")
        if not name or name.startswith("."):
            return None
        p = basis() / name
        p.mkdir(exist_ok=True)
        return p
    p = basis() / wahl
    if not p.is_dir():
        raise Abbruch(_("e_ordner", p=p))
    return p


def waehle_teil(kap, titel):
    teile = []
    for nr, teil, _t in kap:
        eintrag = next((t for t in teile if t[0] == teil), None)
        if eintrag is None:
            teile.append([teil, nr, nr])
        else:
            eintrag[1], eintrag[2] = min(eintrag[1], nr), max(eintrag[2], nr)
    if len(teile) == 1:
        return teile[0][0]
    zeilen = []
    for teil, a, b in teile:
        zeilen += [teil, f"{_('kap_kurz')} {a}–{b}"]
    wahl = zenity("--list", f"--title={titel}", f"--text={_('teil_waehlen')}", *LISTE,
                  f"--column={_('teil')}", f"--column={_('kapitel')}", *zeilen)
    return wahl.split("|")[0] if wahl else None


def kapitel_datei(teil, nr):
    ordner = basis() / teil
    if ordner.is_dir():
        for p in sorted(ordner.iterdir()):
            if (p.suffix == ".xopp" and not p.name.startswith(".")
                    and (p.stem == f"{nr:03d}" or p.stem.startswith(f"{nr:03d} "))):
                return p
    return None


def keine_kapitelliste():
    meldung(_("keine_kapitelliste", pfad=kapitelliste()))


# ---- Commands --------------------------------------------------------------------
def cmd_kapitel(args):
    kap = lade_kapitel()
    if not kap:
        keine_kapitelliste()
        return
    teil = waehle_teil(kap, _("kapitel"))
    if not teil:
        return
    zeilen = []
    for nr, t, titel in kap:
        if t == teil:
            zeilen += [f"{nr:03d}", titel, "✓" if kapitel_datei(teil, nr) else ""]
    wahl = zenity("--list", f"--title={teil}", f"--text={_('kapitel_waehlen')}", *LISTE,
                  f"--column={_('nr')}", f"--column={_('titel')}", f"--column={_('notiz')}", *zeilen)
    if not wahl:
        return
    nr = int(wahl.split("|")[0])
    titel = next(t for n, tl, t in kap if n == nr and tl == teil)
    vorhanden = kapitel_datei(teil, nr)
    if vorhanden:
        aus("OPEN", vorhanden, zaehle_seiten(vorhanden), "ALT")
        return
    aus("OPEN", kapitel_anlegen(teil, nr, titel), 1, "NEU")


def kapitel_anlegen(teil, nr, titel) -> Path:
    """New chapter note: heading only (tags are added in the label bar)."""
    ordner = basis() / teil
    ordner.mkdir(exist_ok=True)
    pfad = ordner / f"{nr:03d} {saubere_name(titel, maxlen=120)}.xopp"
    daten = vorlage_mit_texten([
        (f"{_('kap_kurz')} {nr:03d} – {titel}", TITEL_GROESSE, TITEL_FARBE, *TITEL_POS),
    ])
    schreibe_neu(pfad, daten)
    pruefe_xopp(pfad)
    return pfad


def cmd_ist_kapitel(args):
    p = Path(args[0])
    teile = {t for _n, t, _t in lade_kapitel()}
    ja = (p.parent.name in teile and p.parent.parent.resolve() == basis().resolve()
          and re.match(r"^\d{3}( |$)", p.stem) is not None)
    aus("JA" if ja else "NEIN")


def neue_notiz(ordner: Path) -> Path:
    pfad = eindeutig(ordner / f"{dt.datetime.now():%Y-%m-%d %H-%M}.xopp")
    schreibe_neu(pfad, VORLAGE.read_bytes(), komprimiert=False)
    return pfad


def cmd_neu(args):
    ordner = waehle_ordner(_("neue_notiz"))
    if ordner:
        aus("OPEN", neue_notiz(ordner), 1)


def cmd_neu_eingang(args):
    aus("OPEN", neue_notiz(eingang()), 1)


# ---- PDF ----------------------------------------------------------------------------
def pdf_seiten(pdf: Path):
    """[(width, height), …] in pt, rotation applied. None if pdfinfo is missing."""
    if not shutil.which("pdfinfo"):
        return None
    r = subprocess.run(["pdfinfo", str(pdf)], capture_output=True, text=True, errors="replace")
    m = re.search(r"^Pages:\s+(\d+)", r.stdout, re.M)
    if r.returncode != 0 or not m:
        raise Abbruch(_("e_pdfinfo", n=pdf.name, e=r.stderr.strip()))
    n = int(m.group(1))
    r = subprocess.run(["pdfinfo", "-f", "1", "-l", str(n), str(pdf)],
                       capture_output=True, text=True, errors="replace")
    groessen, drehung = {}, {}
    for z in r.stdout.splitlines():
        m = re.match(r"Page\s+(\d+)\s+size:\s+([\d.]+)\s+x\s+([\d.]+)", z)
        if m:
            groessen[int(m.group(1))] = (float(m.group(2)), float(m.group(3)))
        m = re.match(r"Page\s+(\d+)\s+rot:\s+(-?\d+)", z)
        if m:
            drehung[int(m.group(1))] = int(m.group(2)) % 360
    seiten = []
    for i in range(1, n + 1):
        if i not in groessen:
            raise Abbruch(_("e_seitengroesse", i=i, n=pdf.name))
        b, h = groessen[i]
        if drehung.get(i, 0) in (90, 270):
            b, h = h, b
        seiten.append((b, h))
    return seiten


def pdf_xopp(pdf_name: str, seiten) -> bytes:
    teile = ['<?xml version="1.0" standalone="no"?>',
             '<xournal creator="xournalpp 1.3.3" fileversion="4">',
             "<title>Xournal++ document - see https://xournalpp.github.io/</title>"]
    for i, (b, h) in enumerate(seiten, 1):
        teile.append(f'<page width="{b:g}" height="{h:g}">')
        if i == 1:
            name = html.escape("./" + pdf_name, quote=True)
            teile.append(f'<background type="pdf" domain="absolute" filename="{name}" pageno="1"/>')
            teile += ["<layer/>", "</page>"]
            continue
        teile.append(f'<background type="pdf" pageno="{i}"/>')
        teile += ["<layer/>", "</page>"]
    teile.append("</xournal>")
    return ("\n".join(teile) + "\n").encode("utf-8")


def importiere_pdf(quelle: Path, ordner: Path):
    """Copies the PDF into ordner and creates a .xopp next to it. Returns (xopp, pdf)."""
    if not quelle.is_file():
        raise Abbruch(_("e_nicht_gefunden", p=quelle))
    if quelle.resolve().parent == ordner.resolve():   # already in the target folder
        xopp = quelle.with_suffix(".xopp")
        if xopp.exists():
            return xopp, quelle
        seiten = pdf_seiten(quelle)
        if seiten is None:
            return None, quelle
        schreibe_neu(xopp, pdf_xopp(quelle.name, seiten))
        pruefe_xopp(xopp)
        return xopp, quelle
    gleich = ordner / quelle.name                    # imported before?
    if (gleich.exists() and filecmp.cmp(gleich, quelle, shallow=False)
            and gleich.with_suffix(".xopp").exists()):
        return gleich.with_suffix(".xopp"), gleich
    seiten = pdf_seiten(quelle)
    stamm = saubere_name(quelle.stem) or "PDF"
    for i in range(1, 1000):
        s = stamm if i == 1 else f"{stamm} ({i})"
        ziel_pdf, ziel_xopp = ordner / f"{s}.pdf", ordner / f"{s}.xopp"
        if not ziel_pdf.exists() and not ziel_xopp.exists():
            break
    else:
        raise Abbruch(_("e_kein_name", n=quelle.name))
    shutil.copy2(quelle, ziel_pdf)
    if not filecmp.cmp(quelle, ziel_pdf, shallow=False):
        raise Abbruch(_("e_kopie", p=ziel_pdf))
    if seiten is None:                      # fallback without pdfinfo
        return None, ziel_pdf
    schreibe_neu(ziel_xopp, pdf_xopp(ziel_pdf.name, seiten))
    wurzel = pruefe_xopp(ziel_xopp)
    if len(wurzel.findall("page")) != len(seiten):
        raise Abbruch(_("e_seitenzahl", p=ziel_xopp))
    return ziel_xopp, ziel_pdf


def cmd_pdf(args):
    ziel = None
    if args[:1] == ["--ziel"]:
        ziel, args = args[1], args[2:]
    dateien = [Path(a) for a in args]
    if not dateien:
        start = next((p for p in (Path.home() / "Downloads", Path.home()) if p.is_dir()), Path.home())
        wahl = zenity("--file-selection", "--multiple", "--separator=\n",
                      f"--title={_('pdf_waehlen')}", f"--filename={start}/",
                      "--file-filter=PDF | *.pdf *.PDF", f"--file-filter={_('alle_dateien')} | *")
        if not wahl:
            return
        dateien = [Path(z) for z in wahl.splitlines() if z.strip()]
    if ziel:
        ordner = basis() / ziel
        ordner.mkdir(parents=True, exist_ok=True)
    else:
        vorauswahl = konfig()["pdf_ordner"] or konfig()["eingang"]
        ordner = waehle_ordner(_("pdf_ablegen"), vorauswahl=vorauswahl)
        if not ordner:
            return
        konfig().setze("pdf_ordner", ordner.name)
    erstes, fehler = None, []
    for d in dateien:
        try:
            xopp, pdf = importiere_pdf(d, ordner)
            if xopp is None:
                if erstes is None:
                    erstes = ("PDFFALLBACK", pdf)
            elif erstes is None:
                erstes = ("OPEN", xopp)
        except Abbruch as e:
            fehler.append(str(e))
    if fehler:
        meldung(_("nicht_importiert") + "\n\n".join(fehler), fehler=True)
    if erstes:
        aus(erstes[0], erstes[1], 1)


# ---- Tags -----------------------------------------------------------------------------
LERNSTAND = ("#wdh", "#ok")


def normiere_tag(t):
    t = unicodedata.normalize("NFC", t.strip().lstrip("#").lower())
    t = re.sub(r"[^\w-]", "", t)
    return "#" + t if TAG_RE.match(t) else None


def lerntags_env():
    return dict(os.environ, LERNTAGS_DIR=str(basis()), LERNTAGS_KAPITEL=str(kapitelliste()),
                LERNORDNER_LANG=SPRACHE)


def bekannte_tags():
    """Free tags from `lerntags -l` (without #kNNN and learning status)."""
    if not LERNTAGS.exists():
        return []
    r = subprocess.run([sys.executable, str(LERNTAGS), "-l"], capture_output=True,
                       text=True, encoding="utf-8", errors="replace", env=lerntags_env())
    tags = []
    for z in r.stdout.splitlines():
        m = re.match(r"\s*\d+\s+(#\S+)", z)
        if m:
            t = m.group(1).lower()
            if not re.fullmatch(r"#k\d{3}", t) and t not in LERNSTAND:
                tags.append(t)
    return sorted(set(tags))


def waehle_kapitel_tags():
    kap = lade_kapitel()
    if not kap:
        keine_kapitelliste()
        return []
    teil = waehle_teil(kap, _("kapitel_zuordnen"))
    if not teil:
        return []
    zeilen = []
    for nr, t, titel in kap:
        if t == teil:
            zeilen += ["FALSE", f"{nr:03d}", titel]
    wahl = zenity("--list", "--checklist", f"--title={teil}",
                  f"--text={_('kapitel_ankreuzen')}", *LISTE,
                  "--column=", f"--column={_('nr')}", f"--column={_('titel')}",
                  "--print-column=2", "--separator=\n", *zeilen)
    return [f"#k{int(n):03d}" for n in (wahl or "").splitlines() if n.strip().isdigit()]


def cmd_tags(args):
    zeilen = ["FALSE", f"#wdh  ({_('wdh')})", "#wdh", "FALSE", f"#ok  ({_('ok')})", "#ok"]
    for t in bekannte_tags():
        zeilen += ["FALSE", t, t]
    if lade_kapitel():
        zeilen += ["FALSE", _("kap_zuordnen_eintrag"), "@kapitel"]
    zeilen += ["FALSE", _("neuer_tag_eintrag"), "@neu"]
    wahl = zenity("--list", "--checklist", f"--title={_('tags')}", f"--text={_('tags_ankreuzen')}",
                  *LISTE, "--column=", f"--column={_('tag')}", "--column=key", "--hide-column=3",
                  "--print-column=3", "--separator=\n", *zeilen)
    if wahl is None:
        return
    gewaehlt = [z for z in wahl.splitlines() if z]
    tags = [z for z in gewaehlt if z.startswith("#")]
    if "@kapitel" in gewaehlt:
        tags += waehle_kapitel_tags()
    if "@neu" in gewaehlt:
        eingabe = zenity("--entry", f"--title={_('neuer_tag')}", "--width=480",
                         f"--text={_('neue_tags_text')}")
        ungueltig = []
        for t in (eingabe or "").split():
            n = normiere_tag(t)
            (tags.append(n) if n else ungueltig.append(t))
        if ungueltig:
            meldung(_("tags_ignoriert") + " ".join(ungueltig))
    eindeutige = []
    for t in tags:
        if t not in eindeutige:
            eindeutige.append(t)
    if eindeutige:
        aus("TAGS", " ".join(eindeutige))


def cmd_titel(args):
    vorschlag = args[0] if args else ""
    t = zenity("--entry", f"--title={_('titel')}", "--width=520", f"--text={_('titel_text')}",
               f"--entry-text={vorschlag}")
    t = re.sub(r"\s+", " ", t or "").strip()
    if t:
        aus("TITEL", t)


def cmd_ordner(args):
    vorauswahl, titel = None, None
    while args:
        if args[0] == "--vorauswahl":
            vorauswahl, args = args[1], args[2:]
        elif args[0] == "--titel":
            titel, args = args[1], args[2:]
        else:
            args = args[1:]
    p = waehle_ordner(titel, vorauswahl)
    if p:
        aus("ORDNER", p)


def cmd_suche(args):
    if not LERNTAGS.exists():
        raise Abbruch(_("e_lerntags", p=LERNTAGS))
    r = subprocess.run([sys.executable, str(LERNTAGS), "--waehle", *args],
                       capture_output=True, text=True, encoding="utf-8", env=lerntags_env())
    pfad = r.stdout.strip().splitlines()
    if r.returncode == 0 and pfad and Path(pfad[0]).is_file():
        aus("OPEN", pfad[0])


# ---- Filing (Ablegen) --------------------------------------------------------------------
def cmd_zielname(args):
    quelle, ordner = Path(args[0]), Path(args[1])
    titel = args[2] if len(args) > 2 else ""
    if titel:
        m = re.match(r"(\d{4}-\d{2}-\d{2})", quelle.stem)
        datum = m.group(1) if m else heute()
        rest = saubere_name(titel, maxlen=80 - len(datum) - 1) or "Note"
        stamm = f"{datum} {rest}"
    else:
        stamm = quelle.stem
    ziel = ordner / f"{stamm}.xopp"
    if ziel.exists() and ziel.resolve() == quelle.resolve():
        aus("SELBST", ziel)
        return
    aus("NAME", eindeutig(ziel))


def cmd_zielname_stamm(args):
    """Ziel für Umbenennen/Verschieben mit festem Namen: zielname-stamm QUELLE ORDNER STAMM"""
    quelle, ordner = Path(args[0]), Path(args[1])
    stamm = saubere_name(args[2], maxlen=120)
    if not stamm:
        raise Abbruch(_("e_name_leer"))
    ziel = ordner / f"{stamm}.xopp"
    if ziel.exists() and ziel.resolve() == quelle.resolve():
        aus("SELBST", ziel)
        return
    aus("NAME", eindeutig(ziel))


def unterordner(eltern: Path):
    """Unterordner eines Ordners, sortiert, ohne versteckte."""
    if not eltern.is_dir():
        return []
    return sorted((p for p in eltern.iterdir() if p.is_dir() and not p.name.startswith(".")),
                  key=lambda p: p.name.lower())


def naechste_unternummer(eltern: Path):
    belegt = [int(m.group(1)) for p in unterordner(eltern) if (m := ORDNER_NR_RE.match(p.name))]
    n = max(belegt, default=0) + 1
    if n > 99:
        raise Abbruch(_("e_keine_nummer"))
    return n


def cmd_ordner_neu(args):
    """Ordner unter der Basis, anlegen falls nötig: ordner-neu NAME [--in ORDNER]
    NAME mit oder ohne Nummer; ohne Nummer bekommt ein neuer Ordner die nächste freie.
    --in ORDNER: Unterordner in diesem (obersten) Ordner – mehr Ebenen gibt es nicht.
    Ausgabe: ORDNER<TAB>pfad[<TAB>NEU]"""
    eltern = None
    if "--in" in args:
        i = args.index("--in")
        eltern, args = Path(args[i + 1]), args[:i] + args[i + 2:]
        if not eltern.is_absolute():
            eltern = basis() / eltern
        if eltern.resolve().parent != basis().resolve():
            raise Abbruch(_("e_eine_ebene"))
    name = saubere_name(" ".join(args), maxlen=80)
    if not name or name.startswith("."):
        raise Abbruch(_("e_ordnername"))
    if eltern is not None:
        for p in unterordner(eltern):
            m = ORDNER_NR_RE.match(p.name)
            if p.name.casefold() == name.casefold() or (m and m.group(2).casefold() == name.casefold()):
                aus("ORDNER", p)
                return
        if not ORDNER_NR_RE.match(name):
            name = f"{naechste_unternummer(eltern):02d} {name}"
        p = eltern / name
        p.mkdir(parents=True)
        aus("ORDNER", p, "NEU")
        return
    for p in ordner_liste():                     # vorhandener Ordner, egal welche Schreibweise
        m = ORDNER_NR_RE.match(p.name)
        if p.name.casefold() == name.casefold() or (m and m.group(2).casefold() == name.casefold()):
            aus("ORDNER", p)
            return
    if not ORDNER_NR_RE.match(name):
        name = f"{naechste_ordnernummer():02d} {name}"
    p = basis() / name
    p.mkdir()
    aus("ORDNER", p, "NEU")


DATUM_RE = re.compile(r"^\d{4}-\d{2}-\d{2}")


def cmd_ziel_name(args):
    """Zielpfad fürs Ablegen nach der Nummernlogik: ziel-name QUELLE ORDNERPFAD [TITEL]
    In nummerierten Ordnern heißt eine Notiz "NNN Titel" (Nummer pro Ordner: freies
    Buchkapitel mit gleichem Titel → dessen Nummer; gleiche Notiz im selben Ordner →
    Nummer bleibt; sonst nächste freie). Datums-Namen bleiben ohne Nummer.
    Ausgabe: NAME<TAB>pfad | SELBST<TAB>pfad"""
    quelle, ordner = Path(args[0]), Path(args[1])
    try:
        rel = str(ordner.resolve().relative_to(basis().resolve()))
    except ValueError:
        rel = ordner.name
    m_alt = KAP_DATEI_RE.match(quelle.stem)
    alt_titel = quelle.stem[4:] if m_alt else quelle.stem
    titel = saubere_name(args[2] if len(args) > 2 else "", maxlen=100) or alt_titel
    if nummeriert(ordner.name) and not DATUM_RE.match(titel):
        nr = None
        if m_alt and quelle.parent.resolve() == ordner.resolve():
            nr = int(m_alt.group(1))
        else:
            for n, t, buch in lade_kapitel():
                if t == rel and vergleichbar(saubere_name(buch)) == vergleichbar(titel):
                    if kapitel_datei(rel, n):
                        raise Abbruch(_("e_kapitel_da", t=buch))
                    nr, titel = n, saubere_name(buch)
                    break
        if nr is None:
            nr = naechste_kapitelnummer(rel)
        stamm = f"{nr:03d} {titel}"
    else:
        stamm = titel
    ziel = ordner / f"{stamm}.xopp"
    if ziel.exists() and ziel.resolve() == quelle.resolve():
        aus("SELBST", ziel)
        return
    aus("NAME", eindeutig(ziel))


def cmd_tags_liste(args):
    """Alle bekannten Tags (für Vorschläge): TAG<TAB>#tag"""
    for t in bekannte_tags():
        aus("TAG", t)


def signatur(pfad: Path):
    try:
        s = os.stat(pfad)
    except FileNotFoundError:
        return "-"
    return f"{s.st_ino}:{s.st_mtime_ns}:{s.st_size}"


def vollstaendig(pfad: Path) -> bool:
    try:
        return lies_xml(pfad).rstrip().endswith(b"</xournal>")
    except Exception:
        return False


def cmd_signatur(args):
    """Signature once no earlier save is writing any more (max. 5 s)."""
    pfad = Path(args[0])
    sicherung = Path(str(pfad) + "~")
    ende, letzte, stabil = time.monotonic() + 5, signatur(pfad), 0
    while time.monotonic() < ende and stabil < 3:
        time.sleep(0.1)
        jetzt = signatur(pfad)
        stabil = stabil + 1 if (jetzt == letzte and not sicherung.exists()) else 0
        letzte = jetzt
    aus("SIG", letzte)


def cmd_warte(args):
    """Waits until Xournal++ has rewritten the file (asynchronous SaveJob)."""
    pfad, vorher = Path(args[0]), args[1]
    frist = float(args[2]) if len(args) > 2 else 10.0
    sicherung = Path(str(pfad) + "~")
    ende, letzte, stabil = time.monotonic() + frist, None, 0
    while time.monotonic() < ende:
        time.sleep(0.15)
        jetzt = signatur(pfad)
        if jetzt == "-" or jetzt == vorher or sicherung.exists():
            stabil, letzte = 0, None
            continue
        stabil = stabil + 1 if jetzt == letzte else 0
        letzte = jetzt
        if stabil >= 2 and vollstaendig(pfad):
            aus("OK", jetzt)
            return
    aus("FEHLER", _("e_speichern_zeit", s=frist))


ATTR = re.compile(r'([\w:-]+)="([^"]*)"')


def hintergruende(xml: bytes):
    erg = []
    for m in re.finditer(rb"<background\b[^>]*>", xml):
        attr = {k: html.unescape(v) for k, v in ATTR.findall(m.group(0).decode("utf-8", "replace"))}
        if "filename" in attr:
            erg.append((m, attr))
    return erg


def pdf_bezug(xopp: Path):
    try:
        xml = lies_xml(xopp)
    except Exception:
        return None
    for _m, a in hintergruende(xml):
        if a.get("type") == "pdf" and a.get("domain") == "absolute":
            p = Path(a["filename"])
            return Path(os.path.normpath(p if p.is_absolute() else xopp.parent / p))
    return None


def kopiere_pruefe(quelle: Path, ziel: Path, angelegt: list):
    with open(quelle, "rb") as f_in, open(ziel, "xb") as f_out:
        angelegt.append(ziel)
        shutil.copyfileobj(f_in, f_out)
        f_out.flush()
        os.fsync(f_out.fileno())
    if not filecmp.cmp(quelle, ziel, shallow=False):
        raise Abbruch(_("e_kopie_anders", n=ziel.name))


def cmd_kopiere(args):
    """Copies a note (with PDF and attachments) and verifies everything.
    Prints NEU and the originals to trash after the copy has been opened (MUELL)."""
    quelle, ziel = Path(args[0]), Path(args[1])
    if ziel.exists():
        raise Abbruch(_("e_ziel_existiert", p=ziel))
    if not vollstaendig(quelle):
        raise Abbruch(_("e_unvollstaendig"))
    roh = quelle.read_bytes()
    gz = roh[:2] == b"\x1f\x8b"
    xml = gzip.decompress(roh) if gz else roh
    neu_xml, muell, plan = xml, [quelle], []

    for p in sorted(quelle.parent.iterdir()):      # old-style attachments "<name>.xopp.bg.pdf"
        if p.name.startswith(quelle.name + ".bg") and p.is_file():
            plan.append((p, ziel.with_name(ziel.name + p.name[len(quelle.name):])))
            muell.append(p)

    pdf_erledigt = False
    for m, a in reversed(hintergruende(xml)):
        if a.get("domain") != "absolute":
            continue
        p = Path(a["filename"])
        absolut = Path(os.path.normpath(p if p.is_absolute() else quelle.parent / p))
        if not absolut.is_file():
            raise Abbruch(_("e_hintergrund", p=absolut))
        if a.get("type") == "pdf" and not pdf_erledigt:
            pdf_erledigt = True
            neues_pdf = eindeutig(ziel.with_suffix(".pdf"))
            plan.append((absolut, neues_pdf))
            tag = m.group(0).decode("utf-8")
            alt = re.search(r'filename="[^"]*"', tag).group(0)
            tag_neu = tag.replace(alt, 'filename="%s"' % html.escape("./" + neues_pdf.name, quote=True), 1)
            neu_xml = neu_xml[:m.start()] + tag_neu.encode("utf-8") + neu_xml[m.end():]
            # trash the original PDF only if it sits next to the note and nobody else uses it
            if absolut.parent in (quelle.parent, quelle.parent.resolve()):
                andere = [x for x in quelle.parent.glob("*.xopp")
                          if x != quelle and not x.name.startswith(".") and pdf_bezug(x) == absolut]
                if not andere:
                    muell.append(absolut)
        elif a.get("type") == "pixmap" and not p.is_absolute():
            ziel_bild = Path(os.path.normpath(ziel.parent / p))
            if ziel_bild.exists() and not filecmp.cmp(ziel_bild, absolut, shallow=False):
                raise Abbruch(_("e_bild_konflikt", p=p))
            if not ziel_bild.exists():
                plan.append((absolut, ziel_bild))

    angelegt = []
    try:
        for q, z in plan:
            z.parent.mkdir(parents=True, exist_ok=True)
            kopiere_pruefe(q, z, angelegt)
        if neu_xml == xml:
            kopiere_pruefe(quelle, ziel, angelegt)
        else:
            daten = gzip.compress(neu_xml) if gz else neu_xml
            with open(ziel, "xb") as f:
                angelegt.append(ziel)
                f.write(daten)
                f.flush()
                os.fsync(f.fileno())
            if lies_xml(ziel) != neu_xml:
                raise Abbruch(_("e_kopie_xml"))
            neu_bezug, alt_bezug = pdf_bezug(ziel), pdf_bezug(quelle)
            if not (neu_bezug and alt_bezug and neu_bezug.is_file()
                    and filecmp.cmp(neu_bezug, alt_bezug, shallow=False)):
                raise Abbruch(_("e_kopie_pdf"))
        pruefe_xopp(ziel)
    except Exception:
        if angelegt:                       # never delete – move half-done copies to the trash
            papierkorb(angelegt)
        raise
    autosave = quelle.with_name("." + quelle.stem + ".autosave.xopp")
    if autosave.exists():
        muell.append(autosave)
    aus("NEU", ziel)
    for p in muell:
        aus("MUELL", p)


def papierkorb(pfade):
    korb = basis() / konfig()["papierkorb"]
    korb.mkdir(parents=True, exist_ok=True)
    stempel = f"{dt.datetime.now():%Y-%m-%d %H-%M-%S}"
    for p in pfade:
        p = Path(p)
        if not p.exists():
            continue
        ziel = eindeutig(korb / f"{stempel} {p.name}")
        shutil.move(str(p), str(ziel))
        aus("VERSCHOBEN", ziel)


def cmd_papierkorb(args):
    papierkorb(args)


def cmd_verwerfen(args):
    """Asks whether to discard the note (prints JA/NEIN). Moving happens afterwards (command
    papierkorb) - nothing is deleted for good; the trash is the inbox-level trash folder."""
    name = Path(args[0]).stem if args else ""
    r = zenity("--question", "--no-markup", "--title=Lernordner", "--width=420",
               f"--ok-label={_('verwerfen_ok')}", f"--cancel-label={_('verwerfen_nein')}", "--default-cancel",
               f"--text={_('verwerfen_text', name=name, korb=konfig()['papierkorb'])}")
    aus("JA" if r is not None else "NEIN")


def cmd_ist_vorlage(args):
    p = Path(args[0])
    aus("JA" if p.is_file() and filecmp.cmp(p, VORLAGE, shallow=False) else "NEIN")


def cmd_seiten(args):
    aus("SEITEN", zaehle_seiten(Path(args[0])))


def ist_leer(pfad: Path) -> bool:
    """Leeres Blatt: keine Striche/Bilder/LaTeX, kein PDF-/Bild-Hintergrund und
    höchstens Platzhalter-Texte "#" (alte Vorlage). Tags zählen als Inhalt."""
    try:
        xml = lies_xml(pfad)
    except Exception:
        return False
    if re.search(rb"<(stroke|image|teximage)\b", xml):
        return False
    if re.search(rb'<background\b[^>]*type="(pdf|pixmap)"', xml):
        return False
    for m in re.finditer(rb"<text\b[^>]*>(.*?)</text>", xml, re.S):
        if not re.fullmatch(rb"\s*#?\s*", m.group(1)):
            return False
    return b"</xournal>" in xml


def cmd_aufraeumen(args):
    """Empty sheets from the inbox into the trash (except the last opened one and
    sheets younger than 10 minutes).  aufraeumen --zeigen: only list them."""
    ordner = basis() / konfig()["eingang"]
    if not ordner.is_dir():
        return
    try:
        offen = Path(ZULETZT.read_text(encoding="utf-8").strip()).resolve()
    except OSError:
        offen = None
    weg = []
    grenze = time.time() - 600          # brand-new sheets (just created/opened) stay
    for p in sorted(ordner.iterdir()):
        if (p.suffix == ".xopp" and not p.name.startswith(".") and p.is_file()
                and not p.is_symlink() and p.resolve() != offen and p.stat().st_mtime < grenze
                and ist_leer(p)):
            weg.append(p)
    if args[:1] == ["--zeigen"]:
        for p in weg:
            aus("LEER", p)
        return
    papierkorb(weg)


def text_oder_schluessel(args):
    t = " ".join(args)
    return _(t) if t in TEXTE else t


KAP_DATEI_RE = re.compile(r"^(\d{3})(?: |$)")


def ist_teil(teil):
    """Teil-Ordner = Ordner mit Kapiteln (laut kapitel.tsv oder eigene NNN-Hefte)."""
    if any(t == teil for _, t, _ in lade_kapitel()):
        return True
    ordner = basis() / teil
    return ordner.is_dir() and any(KAP_DATEI_RE.match(x.stem) for x in ordner.glob("*.xopp")
                                   if not x.name.startswith("."))


def cmd_ablage(args):
    """Für das Öffnen-Menü (ohne Dialog).
    ohne Argument:  ORDNER<TAB>name<TAB>anzahl_zettel
    mit Ordner (auch "Ordner/Unterordner"):
                    UNTER<TAB>name<TAB>anzahl  (Unterordner, nur bei obersten Ordnern)
                    NAECHSTER_UNTER<TAB>NN
                    TEIL  (Kapitel können angelegt werden)
                    NUMMERIERT<TAB>nächste Nr.  (Ordner mit "NNN Titel"-Namen)
                    KAPITEL<TAB>anzeige<TAB>pfad_oder_leer<TAB>nr<TAB>BUCH|EIGEN  (nach Nr.)
                    ZETTEL<TAB>anzeige<TAB>pfad  (übrige Notizen, neueste zuerst)"""
    if not args:
        for p in ordner_liste():
            n = sum(1 for x in p.glob("*.xopp") if not x.name.startswith("."))
            aus("ORDNER", p.name, n)
        aus("NAECHSTER", f"{naechste_ordnernummer():02d}")
        return
    teil = args[0]
    ordner = basis() / teil
    dateien = [x for x in ordner.glob("*.xopp") if not x.name.startswith(".")] if ordner.is_dir() else []
    if len(Path(teil).parts) == 1 and ordner.is_dir():
        for u in unterordner(ordner):
            n = sum(1 for x in u.glob("*.xopp") if not x.name.startswith("."))
            aus("UNTER", u.name, n)
        aus("NAECHSTER_UNTER", f"{naechste_unternummer(ordner):02d}")
    kapitel, gesehen = {}, set()
    for nr, t, titel in lade_kapitel():
        if t != teil:
            continue
        p = kapitel_datei(teil, nr)
        if p:
            gesehen.add(p.name)
        kapitel[nr] = (f"{nr:03d} {titel}", p or "", "BUCH")
    for x in sorted(dateien):                 # eigene Kapitel: "NNN Titel.xopp" ohne Eintrag in kapitel.tsv
        m = KAP_DATEI_RE.match(x.stem)
        if m and x.name not in gesehen and int(m.group(1)) not in kapitel:
            kapitel[int(m.group(1))] = (x.stem, x, "EIGEN")
            gesehen.add(x.name)
    if kapitel or ist_teil(teil) or nummeriert(Path(teil).name):
        aus("TEIL")
    if nummeriert(Path(teil).name):
        aus("NUMMERIERT", f"{naechste_kapitelnummer(teil):03d}")
    for nr in sorted(kapitel):
        aus("KAPITEL", kapitel[nr][0], kapitel[nr][1], nr, kapitel[nr][2])
    rest = [x for x in dateien if x.name not in gesehen]
    for p in sorted(rest, key=lambda x: x.stat().st_mtime, reverse=True):
        aus("ZETTEL", p.stem, p)


ORDNER_NR_RE = re.compile(r"^(\d{2}) (.+)$")
FESTE_ORDNER = {"00", "10", "99"}            # Eingang, Prüfungsprotokolle, Archiv


def nummeriert(ordnername):
    """Ordner, in denen Notizen "NNN Titel" heißen (nicht Eingang/Protokolle/Archiv)."""
    m = ORDNER_NR_RE.match(ordnername)
    return bool(m) and m.group(1) not in FESTE_ORDNER


def naechste_kapitelnummer(teil):
    """Pro Ordner: größte Nummer aus kapitel.tsv (dieses Teils) und den NNN-Heften im Ordner + 1."""
    hoechste = max((nr for nr, t, _ in lade_kapitel() if t == teil), default=0)
    ordner = basis() / teil
    if ordner.is_dir():
        for x in ordner.glob("*.xopp"):
            m = KAP_DATEI_RE.match(x.stem)
            if m and not x.name.startswith("."):
                hoechste = max(hoechste, int(m.group(1)))
    if hoechste >= 999:
        raise Abbruch(_("e_keine_nummer"))
    return hoechste + 1


def naechste_ordnernummer():
    """Nächste freie Ordnernummer nach dem letzten regulären Ordner; 10 und 99 bleiben frei."""
    belegt = set()
    for p in ordner_liste():
        m = ORDNER_NR_RE.match(p.name)
        if m:
            belegt.add(int(m.group(1)))
    regulaer = [n for n in belegt if f"{n:02d}" not in FESTE_ORDNER]
    n = max(regulaer, default=0) + 1
    while n in belegt or f"{n:02d}" in FESTE_ORDNER:
        n += 1
    if n > 98:
        raise Abbruch(_("e_keine_nummer"))
    return n


def vergleichbar(s):
    return re.sub(r"\s+", " ", unicodedata.normalize("NFC", s)).strip().casefold()


def cmd_kapitel_titel(args):
    """Kapitel per Titel anlegen/öffnen: kapitel-titel TEIL TITEL
    Gleicher Titel wie ein Buchkapitel dieses Teils → dieses Heft; sonst neues
    eigenes Kapitel mit der nächsten freien Nummer."""
    teil, titel = args[0], " ".join(args[1:]).strip()
    if not saubere_name(titel):
        raise Abbruch(_("e_titel_leer"))
    if not (basis() / teil).is_dir():
        raise Abbruch(_("e_ordner", p=teil))
    for nr, t, buch in lade_kapitel():
        if t == teil and vergleichbar(buch) == vergleichbar(titel):
            aus("OPEN", kapitel_datei(teil, nr) or kapitel_anlegen(teil, nr, buch))
            return
    for x in (basis() / teil).glob("*.xopp"):     # eigenes Kapitel mit gleichem Titel gibt es schon
        m = KAP_DATEI_RE.match(x.stem)
        if m and vergleichbar(x.stem[4:]) == vergleichbar(saubere_name(titel)):
            aus("OPEN", x)
            return
    aus("OPEN", kapitel_anlegen(teil, naechste_kapitelnummer(teil), titel))



def cmd_kapitel_frei(args):
    """All chapters not created yet, in all folders (for the search in the name field):
    FREI<TAB>folder<TAB>no<TAB>title  (only folders that exist)"""
    for nr, teil, titel in lade_kapitel():
        if (basis() / teil).is_dir() and not kapitel_datei(teil, nr):
            aus("FREI", teil, f"{nr:03d}", titel)


def cmd_kapitel_neu(args):
    """Kapitel-Heft öffnen bzw. ohne Dialog anlegen: kapitel-neu TEIL NR"""
    teil, nr = args[0], int(args[1])
    vorhanden = kapitel_datei(teil, nr)
    if vorhanden:
        aus("OPEN", vorhanden)
        return
    titel = next(t for n, _, t in lade_kapitel() if n == nr)
    aus("OPEN", kapitel_anlegen(teil, nr, titel))


def cmd_meldung(args):
    meldung(text_oder_schluessel(args))


def cmd_fehler(args):
    meldung(text_oder_schluessel(args), fehler=True)


def cmd_konfig(args):
    """For main.lua: language, base folder and the name of the inbox folder."""
    aus("SPRACHE", SPRACHE)
    aus("BASIS", basis())
    aus("EINGANG", konfig()["eingang"])


def cmd_sprache(args):
    aus("SPRACHE", SPRACHE)


def cmd_standardbasis(args):
    """Base folder that would be used – without creating anything."""
    cp = configparser.ConfigParser(interpolation=None)
    cp.read(KONFIG, encoding="utf-8")
    b = cp.get("lernordner", "basis", fallback=None) or str(dokumente() / _("basis"))
    aus("BASIS", b)


def cmd_init(args):
    """For the installer: create config (optionally with a base folder) and the inbox."""
    k = konfig()
    if args and args[0].strip():
        k.setze("basis", str(Path(args[0]).expanduser().absolute()))
    aus("BASIS", basis())
    aus("EINGANG", eingang())
    aus("KONFIG", KONFIG)


def cmd_startziel(args):
    """For the launcher: prints the file to open (or nothing = arguments unchanged).
    Must never fail – if in doubt Xournal++ starts normally."""
    try:
        if not args:
            # like paper: open the note that was on top last time
            try:
                letzter = Path(ZULETZT.read_text(encoding="utf-8").strip())
                if letzter.suffix == ".xopp" and letzter.is_file():
                    print(letzter)
                    return
            except OSError:
                pass
            neu = neue_notiz(eingang())
            try:                              # remember at once so "aufraeumen" keeps it
                ZULETZT.parent.mkdir(parents=True, exist_ok=True)
                ZULETZT.write_text(f"{neu}\n", encoding="utf-8")
            except OSError:
                pass
            print(neu)
        elif len(args) == 1 and args[0].lower().endswith(".pdf"):
            xopp, pdf = importiere_pdf(Path(args[0]).expanduser().absolute(), eingang())
            print(xopp or pdf)
    except Exception as e:  # noqa: BLE001
        print(f"lernordner startziel: {e}", file=sys.stderr)


def bildschirm_hoch():
    """True/False depending on the rotation of the (first) logical monitor, None if unknown.
    Mutter DisplayConfig.GetCurrentState: logical monitor = (x, y, scale, transform, …);
    transform 1/3/5/7 = rotated by 90°/270°. The mode size is the unrotated panel size."""
    try:
        text = subprocess.run(
            ["gdbus", "call", "--session", "--dest", "org.gnome.Mutter.DisplayConfig",
             "--object-path", "/org/gnome/Mutter/DisplayConfig",
             "--method", "org.gnome.Mutter.DisplayConfig.GetCurrentState"],
            capture_output=True, text=True, timeout=5).stdout
        modus = re.search(r"\('[^']*', (\d+), (\d+), [\d.]+, [\d.]+, \[[^\]]*\], "
                          r"\{[^}]*'is-current': <true>", text)
        logisch = re.search(r"\(-?\d+, -?\d+, [\d.]+, uint32 (\d+), (?:true|false), \[", text)
        if not modus or not logisch:
            return None
        breit, hoch = int(modus.group(1)), int(modus.group(2))
        if int(logisch.group(1)) % 2 == 1:
            breit, hoch = hoch, breit
        return breit < hoch
    except Exception:  # noqa: BLE001
        return None


def drehen_an():
    try:
        return DREHEN.read_text(encoding="utf-8").strip().startswith("an")
    except OSError:
        return False                          # not asked / never switched on -> do nothing


def cmd_drehen(args):
    """drehen [an|aus|umschalten|status]: switch toolbar/dock following the rotation on or off.
    Prints  DREHEN<TAB>an|aus  (the state after the call)."""
    wahl = args[0] if args else "status"
    jetzt = drehen_an()
    neu = {"an": True, "aus": False, "umschalten": not jetzt, "status": jetzt}.get(wahl)
    if neu is None:
        raise Abbruch(f"drehen: an | aus | umschalten | status (got: {wahl})")
    if neu != jetzt or not DREHEN.exists():
        DREHEN.parent.mkdir(parents=True, exist_ok=True)
        DREHEN.write_text("an\n" if neu else "aus\n", encoding="utf-8")
    aus("DREHEN", "an" if neu else "aus")


def cmd_leiste(args):
    """For the launcher: prints "hoch" (portrait) or "quer" (landscape) and switches
    selectedToolbar in settings.xml between "Lernmodus" and "Lernmodus hoch" - but ONLY if one of
    these two is already selected (whoever did not choose the study toolbar keeps their own).
    Call only while Xournal++ is not running (it rewrites the file on exit). Must never fail.
    'leiste --test' only prints the orientation."""
    import xml.etree.ElementTree as ET
    try:
        hoch = bildschirm_hoch()
        if args and args[0] == "--test":
            print({True: "hoch", False: "quer", None: "unknown"}[hoch])
            return
        if hoch is None or not drehen_an():
            return                             # unknown, or switched off by the user
        print("hoch" if hoch else "quer")            # for the launcher (dock)
        wunsch = "Lernmodus hoch" if hoch else "Lernmodus"
        cfg = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "xournalpp"
        datei = cfg / "settings.xml"
        if not datei.is_file():
            return
        baum = ET.parse(datei, ET.XMLParser(target=ET.TreeBuilder(insert_comments=True)))
        wurzel = baum.getroot()
        for e in wurzel.findall("property"):
            if e.get("name") == "selectedToolbar":
                if e.get("value") not in ("Lernmodus", "Lernmodus hoch") or e.get("value") == wunsch:
                    return                         # another toolbar chosen by the user / already right
                e.set("value", wunsch)
                break
        else:
            return
        sicherung = cfg / "settings.xml.vor-start"
        if not sicherung.exists():
            shutil.copy2(datei, sicherung)
        ET.indent(baum, space="  ")
        tmp = datei.with_name(datei.name + ".tmp")
        baum.write(tmp, encoding="UTF-8", xml_declaration=True)
        ET.parse(tmp)                              # sanity check
        os.replace(tmp, datei)
    except Exception as e:  # noqa: BLE001
        print(f"lernordner leiste: {e}", file=sys.stderr)


BEFEHLE = {
    "leiste": cmd_leiste,
    "kapitel": cmd_kapitel, "ist-kapitel": cmd_ist_kapitel, "neu": cmd_neu,
    "neu-eingang": cmd_neu_eingang, "pdf": cmd_pdf, "tags": cmd_tags, "titel": cmd_titel,
    "ordner": cmd_ordner, "suche": cmd_suche, "zielname": cmd_zielname,
    "signatur": cmd_signatur, "warte": cmd_warte, "kopiere": cmd_kopiere,
    "papierkorb": cmd_papierkorb, "verwerfen": cmd_verwerfen, "drehen": cmd_drehen, "ist-vorlage": cmd_ist_vorlage, "seiten": cmd_seiten,
    "aufraeumen": cmd_aufraeumen, "meldung": cmd_meldung, "fehler": cmd_fehler,
    "startziel": cmd_startziel, "sprache": cmd_sprache, "init": cmd_init, "standardbasis": cmd_standardbasis,
    "zielname-stamm": cmd_zielname_stamm, "ordner-neu": cmd_ordner_neu,
    "ziel-name": cmd_ziel_name, "tags-liste": cmd_tags_liste, "konfig": cmd_konfig,
    "ablage": cmd_ablage, "kapitel-neu": cmd_kapitel_neu, "kapitel-frei": cmd_kapitel_frei, "kapitel-titel": cmd_kapitel_titel,
}


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in BEFEHLE:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    try:
        BEFEHLE[sys.argv[1]](sys.argv[2:])
    except Abbruch as e:
        aus("FEHLER", str(e).replace("\n", " "))
        meldung(str(e), fehler=True)
        sys.exit(1)
    except Exception as e:  # noqa: BLE001
        aus("FEHLER", f"{type(e).__name__}: {e}".replace("\n", " "))
        meldung(_("unerwartet", cmd=sys.argv[1], err=f"{type(e).__name__}: {e}"), fehler=True)
        sys.exit(1)


if __name__ == "__main__":
    main()
