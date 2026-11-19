# Lernordner – study mode for Xournal++

*[Deutsche Version](README.de.md)*

A Xournal++ plugin for handwritten study notes with a pen: chapter notes, annotated PDFs,
tags and filing – **without ever seeing the save dialog**. Built for exam preparation on a
convertible laptop, usable for any subject.

<!-- Screenshot: docs/screenshot.png -->

## What you get

Like paper: exactly one note is open, and it always has a file – **no save dialog, ever**.

- **＋ New** – a fresh sheet in the inbox; the cursor jumps into the **label bar** at the top:
  `01 Folder / 003 Name · #tag #tag`. Type to filter the folder list (↓/↑ choose, → or Enter
  take it and move on), then the name (free chapters from your chapter list are offered), then tags.
  Tapping the page ends it. Folder and name are applied once, with a short "↶ Undo".
- **Numbers per folder** – folders are `NN Name` (a new folder gets the next number),
  notes in numbered folders are `NNN Title` (next free number in that folder, or the number of a
  matching chapter from your list). The inbox (`00`), `10` and `99` stay without note numbers.
- **Tags as chips** – space or comma turns a word into `#tag ×`; suggestions from your existing tags.
  Tags are stored invisibly above the page (not drawn, not exported); `#words` in ordinary text
  boxes count as tags too. A page without tags shows a gentle yellow hint.
- **📂 Open** – recent notes, then folders → notes/chapters, "＋ New chapter", tag search, PDF import.
- **New page** – green ＋ at the end of the document, next to the paper type for the current page
  (lined / squared / dotted / plain). Before adding a page to a page without tags it reminds you once.
- **Thickness & colour** – one pen-friendly menu for line width and colours.
- **🗑 Discard** – throws the open note away before you close it: asks first, opens a fresh sheet, and moves the
  old file to the trash folder (`.trash` in your notes folder) – never deleted for good.
- **⟳ Rotation switch** – a toggle in the toolbar: the toolbar follows the screen rotation (see *Portrait mode*).
- **GNOME search** – press <kbd>Super</kbd> and type a tag, name or folder; matching notes appear
  as their own group (in addition to the usual results) and open in Xournal++.
- Autosave of the real file (every minute, when the window loses focus, before suspend);
  empty sheets are never kept; the next start reopens the last note.
- A launcher (opening a PDF from the file manager imports it) and `lerntags`, a small
  command-line tool that lists and finds tags.

## Requirements

- Linux, **Xournal++ 1.3.x** (written against the 1.3.3 plugin API)
- `python3`, `python3-gi`, `zenity`, `poppler-utils` (for `pdfinfo`)
  `sudo apt install zenity poppler-utils python3-gi`
- **`lua-lgi` for Xournal++'s Lua version (5.4)** – needed for the label bar, 📂 Open and the
  thickness & colour menu. Ubuntu only packages lgi for Lua 5.1/5.3; build lgi 0.9.2 for 5.4 and install it
  below `~/.local/share/lua/5.4` and `~/.local/lib/lua/5.4` (the plugin looks there). `bash install-lgi.sh`
  does exactly that (needs `sudo apt install build-essential pkg-config git liblua5.4-dev libgirepository1.0-dev`).

Developed on Ubuntu with GNOME (Wayland) on a convertible with pen. Other desktops should work – feedback welcome.

## Install

Close Xournal++, then:

```bash
git clone https://github.com/theflow85/xournalpp-lernordner.git
cd xournalpp-lernordner
bash install.sh
```

The installer first asks whether the toolbar should follow the screen rotation, then offers two choices:

- **Standard** (recommended, one question about screen rotation): notes in `~/Documents/Study notes`
  (`~/Dokumente/Lernordner` on German systems), study toolbar active, launcher, touchscreen only
  scrolls/zooms, autosave every 2 minutes, yellow translucent highlighter, fullscreen without menu and sidebar.
- **Custom**: choose the folder and each of these settings yourself.

All files it changes are backed up in `~/.config/xournalpp/lernordner-backups/`.
The plugin is enabled automatically; just start Xournal++.

## Back to the normal interface

<kbd>F10</kbd> (show menu) → **Edit → Toolbars → Xournal++**. Same way back: **Lernmodus**.
<kbd>F11</kbd> toggles fullscreen.

## Portrait mode (tablets / convertibles)

With the study toolbar active, it sits on the left in landscape and moves to the top in portrait (the label
bar stays above it). It follows the rotation of the screen while Xournal++ is running; the installer asks
whether you want that, and the **⟳ button** in the toolbar switches it on and off at any time. If you chose a
toolbar of your own, nothing is touched. In **Custom** install (GNOME with the Ubuntu dock) you can also let the dock
stay fixed in landscape and hide in portrait while Xournal++ runs; it is restored when you quit.
If the dock ever stays hidden (e.g. after a crash of the launcher):
`gsettings reset org.gnome.shell.extensions.dash-to-dock dock-fixed`.

## Chapter list (optional)

The Chapter button needs a tab-separated file `~/.config/xournalpp/lernordner-kapitel.tsv`:

```
# number<TAB>folder<TAB>title
1	01 Basics	Introduction
2	01 Basics	Communication
17	02 Symptoms	Abdominal pain
```

The folder column groups chapters into parts; folders are created when first used.
See [`examples/`](examples/). Without a list, everything else works as usual.

## Safety

- Nothing is ever deleted. Filing first saves, waits until Xournal++ has finished writing,
  copies, verifies the copy byte by byte, opens it – and only then moves the original into the
  hidden `.trash` (`.papierkorb`) folder in your notes folder.
- On any error the original stays where it is.
- Untouched empty notes in the inbox older than a day are moved to the trash folder as well.

## Uninstall

Close Xournal++, then `bash uninstall.sh`. It restores the backed-up settings; your notes stay.

## Known limitations

- No fullscreen button: on GNOME 50 the pen stops working in fullscreen after it leaves the screen
  briefly. The window runs maximised without title bar instead (buttons on the right of the label bar).
- The file manager's (Nautilus) folder search cannot see tags: GNOME's indexer does not read `.xopp`
  contents. Use the overview search (<kbd>Super</kbd>) instead. The search provider becomes active
  after the next login.
- Configuration: `~/.config/xournalpp/lernordner.ini` (folder, inbox name, chapter list).
  Logs: `~/.cache/lernordner.log`, `~/.cache/lernordner-suche.log`.

## How it works

Xournal++ only shows the save dialog when a document has no file path. Lernordner therefore
creates every note as a file first (from `template.xopp`, or a generated `.xopp` with the PDF
as background) and opens that. The Lua plugin drives Xournal++; a Python helper does the
dialogs (zenity) and file work.

## Licence and disclaimer

Copyright © 2026 theflow85. Licensed under the **Creative Commons Attribution-NonCommercial-ShareAlike 4.0
International** licence (CC BY-NC-SA 4.0) – see [LICENSE](LICENSE) or
<https://creativecommons.org/licenses/by-nc-sa/4.0/>. In short: you may use, share and adapt it for
**non-commercial** purposes, with attribution, and adaptations must use the same licence.

**Disclaimer.** This software is provided "as is", without warranty of any kind. It creates, moves, copies and
trashes files in your notes folder and changes Xournal++ settings (backups are made, but nothing is guaranteed).
**Keep your own backups of your notes.** The author is not liable for any loss of data or other damage. Use at
your own risk. Not a medical or professional product. This project is not affiliated with or endorsed by
Xournal++, GNOME or Ubuntu; "Xournal++" belongs to its respective authors and is used here only to describe
what the plugin works with.
