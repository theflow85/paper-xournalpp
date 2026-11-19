-- Lernordner – Xournal++ plugin (written against the 1.3.3 API) · CC BY-NC-SA 4.0
-- https://github.com/theflow85/xournalpp-lernordner
--
-- Grundsatz: Jede Notiz hat von Anfang an einen Dateipfad, damit Xournal++
-- nie den Speicherdialog zeigt. Dialoge (zenity) und Dateiarbeit erledigt
-- lernordner.py im selben Ordner; dieses Skript ruft es auf und liest
-- Zeilen der Form  SCHLÜSSEL<TAB>Wert.

local PLUGIN_DIR = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$")
local HELFER = PLUGIN_DIR .. "/lernordner.py"
local HOME = os.getenv("HOME") or ""
local LOG = HOME .. "/.cache/lernordner.log"

-- lua-lgi für Lua 5.4 ist selbst gebaut und liegt unter ~/.local (Ubuntu hat nur 5.1/5.3)
if not package.path:find(HOME .. "/.local/share/lua/5.4", 1, true) then
  package.path = HOME .. "/.local/share/lua/5.4/?.lua;" .. HOME .. "/.local/share/lua/5.4/?/init.lua;" .. package.path
  package.cpath = HOME .. "/.local/lib/lua/5.4/?.so;" .. package.cpath
end

local function log(...)
  local f = io.open(LOG, "a")
  if f then
    f:write(os.date("%Y-%m-%d %H:%M:%S "), table.concat({ ... }, " "), "\n")
    f:close()
  end
end

-- Textstile (müssen zu lernordner.py passen; daran werden Titel und Tag-Zeile erkannt)
local TITEL_GROESSE, TITEL_FARBE = 22, 0x1a1a1a
local TAG_GROESSE, TAG_FARBE = 10, 0x808080
local SCHRIFT = "Sans"
local LERNSTAND = { ["#wdh"] = true, ["#ok"] = true }

------------------------------------------------------------------------------
-- Hilfsfunktionen
------------------------------------------------------------------------------
local function q(s)
  return "'" .. (tostring(s):gsub("'", "'\\''")) .. "'"
end

local function split(s, sep)
  local t = {}
  for teil in (s .. sep):gmatch("(.-)" .. sep) do t[#t + 1] = teil end
  return t
end

-- GLib aus lua-lgi (für Hintergrund-Aufrufe); nil, wenn lgi fehlt
local glib_cache = nil
local function glib()
  if glib_cache == nil then
    local ok, lgi = pcall(require, "lgi")
    glib_cache = (ok and type(lgi) == "table" and lgi.GLib) or false
  end
  return glib_cache or nil
end

local function zerlege(out)
  local res = {}
  for zeile in out:gmatch("[^\n]+") do
    local key, rest = zeile:match("^(%u+)\t?(.*)$")
    if key then
      local e = split(rest, "\t")
      e.key = key
      res[#res + 1] = e
    end
  end
  return res
end

-- Ruft lernordner.py auf; liefert Liste von {key=…, [1]=…, [2]=…}.
-- Innerhalb eines Knopf-Ablaufs (Koroutine, siehe im_hintergrund) läuft der
-- Helfer im Hintergrund: Xournal++ bleibt ansprechbar (sonst meldet GNOME
-- "antwortet nicht", solange ein zenity-Dialog offen ist). Ohne lgi oder
-- außerhalb einer Koroutine wie früher blockierend.
local function helfer(...)
  local cmd = "python3 " .. q(HELFER)
  for _, a in ipairs({ ... }) do cmd = cmd .. " " .. q(a) end
  local co, haupt = coroutine.running()
  local GLib = glib()
  -- Nicht pausierbar (Hauptschleife, oder GTK-Rückruf, der synchron aus einem Ablauf heraus
  -- ausgelöst wurde – z. B. set_text/grab_focus → on_changed): dann blockierend aufrufen.
  if haupt or not GLib or not coroutine.isyieldable() then
    local f = io.popen(cmd .. " 2>>" .. q(LOG), "r")
    if not f then return {} end
    local out = f:read("a") or ""
    f:close()
    return zerlege(out)
  end
  local basis = os.tmpname()
  local aus, fertig = basis .. ".aus", basis .. ".fertig"
  os.remove(basis)
  os.execute("(" .. cmd .. " >" .. q(aus) .. " 2>>" .. q(LOG) .. "; echo $? >" .. q(fertig) .. ") &")
  GLib.timeout_add(GLib.PRIORITY_DEFAULT, 100, function()
    local f = io.open(fertig, "r")
    if not f then return true end          -- Helfer läuft noch
    f:close()
    local a = io.open(aus, "r")
    local out = a and a:read("a") or ""
    if a then a:close() end
    os.remove(aus); os.remove(fertig)
    local ok, err = coroutine.resume(co, zerlege(out))
    if not ok then log("Ablauf-Fehler:", tostring(err)) end
    return false
  end)
  return coroutine.yield()
end

-- Macht aus einem Knopf-Ablauf eine Koroutine. Läuft schon ein Ablauf (z. B.
-- ein Dialog ist offen), wird der Klick ignoriert – keine gestapelten Fenster.
local beschaeftigt = false
local function im_hintergrund(name, ablauf)
  return function(...)
    if beschaeftigt then
      log(name .. ": ignoriert, es läuft noch ein anderer Ablauf")
      return
    end
    beschaeftigt = true
    local args = table.pack(...)
    local co = coroutine.create(function()
      local ok, err = pcall(ablauf, table.unpack(args, 1, args.n))
      if not ok then log(name .. ":", tostring(err)) end
      beschaeftigt = false
    end)
    local ok, err = coroutine.resume(co)
    if not ok then
      log(name .. ":", tostring(err))
      beschaeftigt = false
    end
  end
end

local function erstes(res, key)
  for _, e in ipairs(res) do
    if e.key == key then return e end
  end
  return nil
end

-- text = message key from lernordner.py (translated there) or plain text
local function meldung(text) helfer("meldung", text) end
local function fehler(text) helfer("fehler", text) end

-- Sprache (wie lernordner.py) und kleine Übersetzungshilfe: T("deutsch", "english")
local function sprache()
  for _, v in ipairs({ "LERNORDNER_LANG", "LC_ALL", "LC_MESSAGES", "LANG", "LANGUAGE" }) do
    local w = os.getenv(v)
    if w and w ~= "" then return w:lower():sub(1, 2) == "de" and "de" or "en" end
  end
  return "en"
end
local DE = sprache() == "de"
local function T(de, en) return DE and de or en end

-- Name des Eingangsordners aus lernordner.ini (z. B. "00 Eingang" / "00 Inbox"), einmal erfragt
local eingang_cache = nil
local function EINGANG()
  if not eingang_cache then
    local e = erstes(helfer("konfig"), "EINGANG")
    eingang_cache = e and e[1] or T("00 Eingang", "00 Inbox")
  end
  return eingang_cache
end
local function im_eingang(pfad)
  local ordner = pfad:match("([^/]+)/[^/]+$")
  return ordner ~= nil and ordner == EINGANG()
end

local function existiert(pfad)
  local f = io.open(pfad, "rb")
  if f then f:close() return true end
  return false
end

-- KEIN Vollbild: Im Vollbildmodus verliert GNOME 50 (mutter) nach jedem vom
-- Kernel erzwungenen Stift-prox-out den Stift, bis ein Fingertipp kommt
-- (belegt 2026-11-07, siehe CLAUDE.md). Der Lernmodus läuft maximiert ohne Menüleiste.

------------------------------------------------------------------------------
-- Speichern ohne Dialog und Dokumentwechsel
------------------------------------------------------------------------------

-- Speichert die aktuelle Notiz (hat einen Pfad) und wartet, bis die Datei
-- vollständig geschrieben ist. true bei Erfolg.
local function speichern_und_warten(pfad)
  local sig = erstes(helfer("signatur", pfad), "SIG")
  app.activateAction("save")
  local ok = erstes(helfer("warte", pfad, sig and sig[1] or "-"), "OK")
  return ok ~= nil
end

-- Leeres Blatt? (wird nicht gespeichert; aus dem Eingang beim Wechsel in den Papierkorb)
-- Leer = kein PDF, keine Seite beschrieben; auf der aktuellen Seite zählen alte
-- Platzhalter-Texte "#" nicht. Tags (unsichtbar über der Seite) zählen als Inhalt.
local function nur_platzhalter()
  if #app.getStrokes("layer") > 0 or #app.getImages("layer") > 0 then return false end
  for _, t in ipairs(app.getTexts("layer")) do
    if not t.text:match("^%s*#%s*$") then return false end
  end
  return true
end

function ist_leer(ds)
  if ds.pdfBackgroundFilename and ds.pdfBackgroundFilename ~= "" then return false end
  for i, p in ipairs(ds.pages) do
    if p.pdfBackgroundPageNo and p.pdfBackgroundPageNo > 0 then return false end
    if p.isAnnotated and (i ~= ds.currentPage or not nur_platzhalter()) then return false end
  end
  return true
end

-- Öffnet ziel (Seite seite oder letzte Position). Die aktuelle Notiz wird vorher
-- still gespeichert; app.openFile(…, true) würde Ungespeichertes sonst verwerfen.
local function wechsle_zu(ziel, seite)
  local ds = app.getDocumentStructure()
  local aktuell = ds.xoppFilename
  if aktuell == ziel then
    if seite then app.scrollToPage(seite) end
    return true
  end
  if aktuell ~= "" then
    local leer = ist_leer(ds)
    if not leer then
      if not speichern_und_warten(aktuell) then
        fehler(T("Die aktuelle Notiz konnte nicht gespeichert werden.\n", "The current note could not be saved.\n") ..
               T("Es wurde nichts geöffnet.\n\n", "Nothing was opened.\n\n") .. aktuell)
        return false
      end
    end
    app.openFile(ziel, seite, true)
    -- Wie Papier: ein leeres, unbenutztes Blatt aus dem Eingang wird nicht aufgehoben
    if leer and im_eingang(aktuell) and app.getDocumentStructure().xoppFilename == ziel then
      helfer("papierkorb", aktuell)
    end
  else
    -- Dokument ohne Pfad (z. B. direkt geöffnetes PDF): Xournal++ fragt nach,
    -- falls es ungespeicherte Änderungen gibt.
    app.openFile(ziel, seite, false)
  end
  return true
end

------------------------------------------------------------------------------
-- Texte auf Seiten (Titel, Tag-Zeile)
------------------------------------------------------------------------------
local function ist_titel(t)
  return t.font and t.font.size == TITEL_GROESSE and t.color == TITEL_FARBE
end

local function ist_tagzeile(t)
  return t.font and t.font.size == TAG_GROESSE and t.color == TAG_FARBE
         and t.text:match("^%s*#") ~= nil
end

-- Führt f() mit Seite nr als aktueller Seite aus und stellt die Seite danach zurück.
local function auf_seite(nr, f)
  local alt = app.getDocumentStructure().currentPage
  if alt ~= nr then app.setCurrentPage(nr) end
  local ok, a, b = pcall(f)
  if alt ~= nr then app.setCurrentPage(alt) end
  if not ok then error(a) end
  return a, b
end

-- Texteditor beenden, damit "delete" nicht ein Zeichen im Textfeld löscht
local function texteditor_beenden()
  pcall(function()
    if app.getActionState("select-tool") == app.C.Tool_text then
      app.changeActionState("select-tool", app.C.Tool_pen)
    end
  end)
end

local function finde_text(pruef)
  for _, t in ipairs(app.getTexts("layer")) do
    if pruef(t) then return t end
  end
  return nil
end

local function ersetze_text(alt, text, groesse, farbe, x, y)
  if alt then
    x, y = alt.x, alt.y
    app.addToSelection({ alt.ref })
    app.activateAction("delete")
  end
  app.addTexts({
    texts = { { text = text, font = { name = SCHRIFT, size = groesse }, color = farbe, x = x, y = y } },
    allowUndoRedoAction = "grouped",
  })
  app.clearSelection()
  -- Seite neu zeichnen lassen: Läuft der Ablauf im Hintergrund (nach einem Dialog),
  -- zeichnet Xournal++ sonst nichts oder nur einen Teil neu (Tag-Zeile fehlte/abgeschnitten).
  pcall(app.refreshPage)
end

------------------------------------------------------------------------------
-- Knöpfe
------------------------------------------------------------------------------
-- ＋ Neu: frisches Blatt im Eingang (ist das aktuelle Blatt dort noch leer, bleibt es),
-- danach springt der Cursor in die Etikett-Leiste: Ordner → Name → Tags
function lernNeu()
  local ds = app.getDocumentStructure()
  if not (im_eingang(ds.xoppFilename) and ist_leer(ds)) then
    local e = erstes(helfer("neu-eingang"), "OPEN")
    if not e or not wechsle_zu(e[1], 1) then return end
  end
  local GLib = glib()
  if GLib and etikett_ablage_starten then
    GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, function() pcall(etikett_ablage_starten) return false end)
  end
end

function lernPdf()
  local res = helfer("pdf")
  local e = erstes(res, "OPEN")
  if e then
    wechsle_zu(e[1], 1)
    return
  end
  local fb = erstes(res, "PDFFALLBACK")             -- nur ohne pdfinfo
  if fb then
    if wechsle_zu(fb[1], 1) then app.activateAction("save") end
  end
end

function lernSuche()
  local e = erstes(helfer("suche"), "OPEN")
  if e then wechsle_zu(e[1], nil) end
end

------------------------------------------------------------------------------
-- Ausklappmenü "Dicke und Farbe" (GTK-Popover über lua-lgi)
-- Die schwebende Werkzeugbox von Xournal++ schließt sich mit dem Stift
-- unzuverlässig (siehe CLAUDE.md), daher ein eigenes Popover am Knopf.
------------------------------------------------------------------------------
local STIFT_SYMBOL = "lernordner-dicke"
local FARB_WERKZEUGE = { [1] = true, [3] = true, [4] = true }  -- Stift, Marker, Text
-- Stufen app.C.ToolSize_* 0..4; Strichbreite der Vorschau in Pixeln
local DICKEN = { { 0, 1 }, { 1, 2 }, { 2, 3.5 }, { 3, 5.5 }, { 4, 9 } }
-- Palette xournal.gpl: Schwarz, Blau, Rot, Grün
local FARBEN = { 0x000000, 0x3333CC, 0xFF0000, 0x008000 }
local KNOPF = 44                                               -- Kantenlänge (Stift-tauglich)

local gtk_cache = nil   -- { Gtk = …, lgi = … } oder false (nicht verfügbar)
local function gtk()
  if gtk_cache == nil then
    local ok, lgi = pcall(require, "lgi")
    if ok and type(lgi) == "table" then
      local okG, Gtk = pcall(lgi.require, "Gtk", "3.0")
      gtk_cache = okG and { lgi = lgi, Gtk = Gtk } or false
      if not okG then log("lgi: Gtk 3.0 nicht ladbar:", tostring(Gtk)) end
    else
      gtk_cache = false
      log("lgi nicht ladbar:", tostring(lgi))
    end
  end
  return gtk_cache or nil
end

-- Sucht im Xournal-Fenster das Widget eines Leistenknopfs (am Symbolnamen).
local function finde_knopf(Gtk, symbol)
  symbol = symbol or STIFT_SYMBOL
  local treffer = nil
  local function suche(w)
    if treffer then return end
    if (Gtk.ToolButton:is_type_of(w) or Gtk.Image:is_type_of(w)) and w.icon_name == symbol
       and w:get_mapped() then
      treffer = w
      return
    end
    if Gtk.Container:is_type_of(w) then w:forall(suche) end
  end
  for _, fenster in ipairs(Gtk.Window.list_toplevels()) do
    if fenster:get_visible() then suche(fenster) end
    if treffer then break end
  end
  return treffer
end

local function aktuelle_dicke()
  local ok, s = pcall(app.getActionState, "tool-size")
  return ok and s or nil
end

local function waehle_dicke(stufe)
  local ok, err = pcall(app.changeActionState, "tool-size", stufe)
  if not ok then log("tool-size:", tostring(err)) end
end

local function waehle_farbe(farbe)
  local ok, err = pcall(function()
    if not FARB_WERKZEUGE[app.getActionState("select-tool")] then
      app.changeActionState("select-tool", app.C.Tool_pen)
    end
    if farbe then
      app.changeToolColor({ color = farbe })
    else
      app.activateAction("select-color")
    end
  end)
  if not ok then log("Farbe:", tostring(err)) end
end

local offenes_popover = nil

local function baue_popover(Gtk, anker)
  -- modal = false: ein modales Popover greift den Stift (Grab); unter Wayland blieb
  -- der Stift danach teils "hängen". Schließen: Auswahl oder erneuter Tipp auf den Knopf.
  local pop = Gtk.Popover { relative_to = anker, position = Gtk.PositionType.RIGHT, modal = false }
  local raster = Gtk.Grid { row_spacing = 4, column_spacing = 4, margin = 6 }

  local vordergrund = { 0.15, 0.15, 0.15 }
  local function knopf(zeichne, aktion)
    local b = Gtk.Button { relief = Gtk.ReliefStyle.NONE, can_focus = false }
    local flaeche = Gtk.DrawingArea { width_request = KNOPF, height_request = KNOPF }
    function flaeche:on_draw(cr)
      -- Textfarbe des Designs (hell im dunklen, dunkel im hellen Design)
      local ok_f, fg = pcall(function() return self:get_style_context():get_color(self:get_state_flags()) end)
      vordergrund = (ok_f and fg) and { fg.red, fg.green, fg.blue } or { 0.15, 0.15, 0.15 }
      local ok, err = pcall(zeichne, cr, self:get_allocated_width(), self:get_allocated_height())
      if not ok then log("Zeichnen:", tostring(err)) end
      return true
    end
    b:add(flaeche)
    function b:on_clicked()
      pop:popdown()
      aktion()
    end
    return b
  end

  local jetzt = aktuelle_dicke()
  for i, d in ipairs(DICKEN) do
    local stufe, breite = d[1], d[2]
    raster:attach(knopf(function(cr, w, h)
      if stufe == jetzt then
        cr:set_source_rgba(0.2, 0.4, 0.9, 0.18)
        cr:rectangle(2, 2, w - 4, h - 4)
        cr:fill()
      end
      cr:set_source_rgb(vordergrund[1], vordergrund[2], vordergrund[3])
      cr:set_line_width(breite)
      cr:set_line_cap(1)  -- CAIRO_LINE_CAP_ROUND
      cr:move_to(10, h / 2)
      cr:line_to(w - 10, h / 2)
      cr:stroke()
    end, function() waehle_dicke(stufe) end), i - 1, 0, 1, 1)
  end

  for i, farbe in ipairs(FARBEN) do
    local r, g, b = (farbe >> 16 & 0xff) / 255, (farbe >> 8 & 0xff) / 255, (farbe & 0xff) / 255
    raster:attach(knopf(function(cr, w, h)
      cr:set_source_rgb(r, g, b)
      cr:arc(w / 2, h / 2, 13, 0, 2 * math.pi)
      cr:fill()
      -- feiner Ring, damit auch Schwarz auf dunklem Grund sichtbar ist
      cr:set_source_rgba(vordergrund[1], vordergrund[2], vordergrund[3], 0.45)
      cr:set_line_width(1.5)
      cr:arc(w / 2, h / 2, 14, 0, 2 * math.pi)
      cr:stroke()
    end, function() waehle_farbe(farbe) end), i - 1, 1, 1, 1)
  end

  -- "Weitere Farbe…": Regenbogen-Ring öffnet den Farbdialog von Xournal++
  raster:attach(knopf(function(cr, w, h)
    local teile = { { 1, 0, 0 }, { 1, 0.6, 0 }, { 1, 1, 0 }, { 0, 0.7, 0 }, { 0, 0.5, 1 }, { 0.6, 0, 0.8 } }
    cr:set_line_width(5)
    for k, c in ipairs(teile) do
      cr:set_source_rgb(c[1], c[2], c[3])
      cr:arc(w / 2, h / 2, 11, (k - 1) * math.pi / 3, k * math.pi / 3)
      cr:stroke()
    end
  end, function() waehle_farbe(nil) end), 4, 1, 1, 1)

  pop:add(raster)
  raster:show_all()
  return pop
end

function lernStift()
  local g = gtk()
  if not g then
    meldung(T("Für das Menü „Dicke und Farbe“ fehlt lua-lgi für Lua 5.4. Siehe Log: ~/.cache/lernordner.log",
              "The thickness & colour menu needs lua-lgi for Lua 5.4. See log: ~/.cache/lernordner.log"))
    return
  end
  local ok, err = pcall(function()
    local Gtk = g.Gtk
    if offenes_popover then
      local war_offen = offenes_popover:get_visible()
      offenes_popover:destroy()
      offenes_popover = nil
      if war_offen then return end   -- zweiter Tipp auf den Knopf schließt das Menü
    end
    local anker = finde_knopf(Gtk)
    if not anker then
      log("Knopf mit Symbol", STIFT_SYMBOL, "nicht gefunden")
      meldung(T("Der Knopf für Dicke und Farbe wurde im Fenster nicht gefunden (siehe ~/.cache/lernordner.log).",
                "The thickness & colour button was not found in the window (see ~/.cache/lernordner.log)."))
      return
    end
    offenes_popover = baue_popover(Gtk, anker)
    offenes_popover:popup()
  end)
  if not ok then
    log("lernStift:", tostring(err))
    meldung(T("Menü „Dicke und Farbe“ konnte nicht geöffnet werden:\n", "Could not open the thickness & colour menu:\n") .. tostring(err))
  end
end

------------------------------------------------------------------------------
-- Automatisch speichern und "zuletzt"-Zettel merken
-- Xournals eigenes Autosave schreibt nur eine Sicherungskopie (.Name.autosave.xopp),
-- nicht die Notiz. Wir speichern die Notiz selbst: jede Minute, wenn das Fenster
-- inaktiv wird (auch beim Zuklappen: Sperrbildschirm) und vor dem Schlafmodus.
------------------------------------------------------------------------------
local verbunden = { fenster = nil, dbus = nil, etikett = nil }
local ZULETZT = (os.getenv("XDG_STATE_HOME") or (HOME .. "/.local/state")) .. "/lernordner/zuletzt"
local letzter_pfad = nil

local VERLAUF = ZULETZT:match("^(.*)/[^/]*$") .. "/verlauf"      -- zuletzt geöffnete, neueste zuerst
local AUFTRAG = ZULETZT:match("^(.*)/[^/]*$") .. "/oeffnen"      -- von lernordner-suche (GNOME-Suche)

function lies_verlauf()
  local liste = {}
  local f = io.open(VERLAUF, "r")
  if f then
    for z in f:lines() do if z ~= "" then liste[#liste + 1] = z end end
    f:close()
  end
  return liste
end

local function merke_zuletzt(pfad)
  if pfad == letzter_pfad or pfad == "" or not pfad:match("%.xopp$") then return end
  letzter_pfad = pfad
  os.execute("mkdir -p " .. q(ZULETZT:match("^(.*)/[^/]*$")))
  local f = io.open(ZULETZT, "w")
  if f then f:write(pfad, "\n"); f:close() end
  local neu = { pfad }
  for _, p in ipairs(lies_verlauf()) do
    if p ~= pfad and #neu < 30 then neu[#neu + 1] = p end
  end
  f = io.open(VERLAUF, "w")
  if f then f:write(table.concat(neu, "\n"), "\n"); f:close() end
end

-- Auftrag aus der GNOME-Suche: Notiz im laufenden Fenster öffnen
local function auftrag_abholen()
  local f = io.open(AUFTRAG, "r")
  if not f then return end
  local pfad = (f:read("l") or ""):gsub("%s+$", "")
  f:close()
  if beschaeftigt then return end                 -- später nochmal
  os.remove(AUFTRAG)
  if pfad ~= "" and existiert(pfad) and lernOeffneDatei then
    lernOeffneDatei(pfad)
    if verbunden.fenster then pcall(function() verbunden.fenster:present() end) end
  end
end

local function auto_speichern(grund)
  if beschaeftigt then return end                -- ein Ablauf speichert/öffnet gerade selbst
  local ok, err = pcall(function()
    local ds = app.getDocumentStructure()
    if ds.xoppFilename == "" then return end
    if app.getActionState("select-tool") == app.C.Tool_text then return end  -- Tippen nicht stören
    if ist_leer(ds) then return end              -- leere Blätter nicht speichern
    app.activateAction("save")
  end)
  if not ok then log("Autospeichern (" .. grund .. "):", tostring(err)) end
end

local etikett_einhaengen   -- Etikett-Leiste, unten definiert

local function verbinde_ereignisse()
  local g = gtk()
  if not g then return end
  -- Fenster wird inaktiv (anderes Fenster, Sperrbildschirm beim Zuklappen) → speichern
  if not verbunden.fenster then
    local groesstes, flaeche = nil, 0
    for _, w in ipairs(g.Gtk.Window.list_toplevels()) do
      if w:get_visible() and g.Gtk.ApplicationWindow:is_type_of(w) then
        local a = w:get_allocated_width() * w:get_allocated_height()
        if a > flaeche then groesstes, flaeche = w, a end
      end
    end
    if groesstes then
      groesstes.on_notify["is-active"] = function(w)
        if not w.is_active then auto_speichern("Fenster inaktiv") end
      end
      verbunden.fenster = groesstes
    end
  end
  -- Etikett-Leiste (Ordner / Name · #tags) ins Overlay des Hauptfensters
  if verbunden.fenster and verbunden.etikett == nil and etikett_einhaengen then
    local ok, err = pcall(etikett_einhaengen, verbunden.fenster)
    if not ok then log("Etikett-Leiste:", tostring(err)) end
    verbunden.etikett = ok and err or false       -- false: nicht immer wieder versuchen
  end
  -- Schlafmodus (logind PrepareForSleep) → speichern
  if not verbunden.dbus then
    local ok, err = pcall(function()
      local Gio = g.lgi.Gio
      local bus = Gio.bus_get_sync(Gio.BusType.SYSTEM)
      bus:signal_subscribe("org.freedesktop.login1", "org.freedesktop.login1.Manager",
        "PrepareForSleep", "/org/freedesktop/login1", nil, Gio.DBusSignalFlags.NONE,
        function() auto_speichern("Schlafmodus") end)
      verbunden.dbus = bus
    end)
    if not ok then log("Schlafmodus-Signal:", tostring(err)); verbunden.dbus = false end
  end
end

-- Leiste je nach Ausrichtung umschalten (Lernmodus links / Lernmodus hoch oben), auch bei laufendem
-- Xournal++: Fensteraktion "win.select-toolbar" (Zielwert = Name des Layouts), per lgi ausgelöst.
-- Ausrichtung = Größe des Monitors, auf dem das Fenster liegt (GDK: schon gedreht). Erst wenn sie
-- zwei Takte (4 s) gleich bleibt, damit ein Dreh-Übergang nicht flackert.
-- Nur umschalten, wenn der Nutzer das Lernmodus-Layout gewählt hat (eine eigene Leiste bleibt unberührt).
local leiste = { wunsch = nil, zaehler = 0, versuche = 0, gesetzt = nil, start_layout = nil, symbol = nil, takt = 0 }
-- Schalter "Leiste folgt der Drehung" (Knopf LERN_DREHEN; Zustand in ~/.local/state/lernordner/drehen)
local DREHEN_DATEI = (os.getenv("XDG_STATE_HOME") or (HOME .. "/.local/state")) .. "/lernordner/drehen"
local DREHEN_AN, DREHEN_AUS = "lernordner-drehen-symbolic", "lernordner-drehen-aus-symbolic"
local function drehen_aktiv()
  local f = io.open(DREHEN_DATEI, "rb")
  if not f then return false end
  local t = f:read("a"); f:close()
  return t:match("^%s*an") ~= nil
end
-- Das Symbol des Knopfs zeigt den Zustand (nach jedem Umbau der Leiste neu setzen)
local function drehen_symbol()
  local g = gtk()
  if not g then return end
  local an = drehen_aktiv()
  local k = finde_knopf(g.Gtk, an and DREHEN_AUS or DREHEN_AN)   -- das jeweils falsche Symbol suchen
  if k then k.icon_name = an and DREHEN_AN or DREHEN_AUS end
  leiste.symbol = an
end
local function gewaehltes_layout_aus_settings()
  if leiste.start_layout == nil then
    leiste.start_layout = false
    local cfg = os.getenv("XDG_CONFIG_HOME") or (HOME .. "/.config")
    local f = io.open(cfg .. "/xournalpp/settings.xml", "rb")
    if f then
      local text = f:read("a"); f:close()
      leiste.start_layout = text:match('name="selectedToolbar"%s+value="([^"]*)"') or false
    end
  end
  return leiste.start_layout
end
local function ist_lernmodus(name) return name == "Lernmodus" or name == "Lernmodus hoch" end
local function leiste_pruefen()
  local g = gtk()
  local fenster = verbunden.fenster
  if not (g and fenster) then return end
  local gdkfenster = fenster:get_window()
  if not gdkfenster then return end
  local aktiv = drehen_aktiv()
  leiste.takt = leiste.takt + 1
  if leiste.symbol ~= aktiv or leiste.takt % 15 == 0 then pcall(drehen_symbol) end
  if not aktiv then leiste.wunsch = nil; return end                  -- vom Nutzer ausgeschaltet
  local Gdk = g.lgi.Gdk
  local monitor = Gdk.Display.get_default():get_monitor_at_window(gdkfenster)
  if not monitor then return end
  local geo = monitor:get_geometry()
  local wunsch = (geo.width < geo.height) and "Lernmodus hoch" or "Lernmodus"
  if wunsch ~= leiste.wunsch then leiste.wunsch, leiste.zaehler, leiste.versuche = wunsch, 0, 0 end
  leiste.zaehler = leiste.zaehler + 1
  if leiste.zaehler < 2 then return end
  -- Ubuntu-Dock: quer fest, hoch ausgeblendet – nur wenn der Starter es erlaubt hat (er stellt es beim
  -- Beenden wieder her), sonst bliebe es nach dem Schließen verstellt
  if leiste.dock ~= wunsch and os.getenv("LERNORDNER_DOCK") == "1" then
    leiste.dock = wunsch
    os.execute("gsettings set org.gnome.shell.extensions.dash-to-dock dock-fixed "
      .. (wunsch == "Lernmodus" and "true" or "false") .. " >/dev/null 2>&1 &")
  end
  if leiste.versuche >= 3 then return end
  local aktion = fenster:lookup_action("select-toolbar")
  if not aktion then
    leiste.versuche = 3
    log("Leiste: Aktion select-toolbar nicht gefunden")
    return
  end
  -- Zustand der Aktion (gewähltes Layout), falls lesbar
  local okS, ist = pcall(function() return aktion:get_state():get_string() end)
  if not okS then ist = gewaehltes_layout_aus_settings() end   -- Zustand nicht lesbar: Stand beim Start
  if not ist_lernmodus(ist) then return end                    -- eigene Leiste des Nutzers: nichts anfassen
  if okS and ist == wunsch then leiste.versuche = 0; leiste.gesetzt = wunsch; return end
  if not okS and leiste.gesetzt == wunsch then return end
  local typ = aktion:get_parameter_type()
  local typtext = typ and typ:dup_string() or "nil"
  leiste.versuche = leiste.versuche + 1
  if typtext ~= "s" then
    leiste.versuche = 3
    log("Leiste: select-toolbar erwartet Typ", typtext, "statt s")
    return
  end
  log("Leiste: wechsle zu", wunsch)
  aktion:activate(g.lgi.GLib.Variant("s", wunsch))
  leiste.gesetzt = wunsch
  leiste.symbol = nil                                                -- Leiste neu aufgebaut → Symbol neu setzen
end

-- Alle 2 s: zuletzt-Zettel merken, Ereignisse verbinden; alle 60 s speichern
local takt = 0
local function beobachter()
  takt = takt + 1
  local ok, err = pcall(function()
    merke_zuletzt(app.getDocumentStructure().xoppFilename)
    auftrag_abholen()
    if not verbunden.fenster or verbunden.dbus == nil or verbunden.etikett == nil then verbinde_ereignisse() end
    if takt % 30 == 0 then auto_speichern("Minute") end
    local okL, errL = pcall(leiste_pruefen)
    if not okL then leiste.versuche = leiste.versuche + 1; log("Leiste:", tostring(errL)) end
  end)
  if not ok then log("Beobachter:", tostring(err)) end
  return true
end

------------------------------------------------------------------------------
-- 📂 Öffnen: Popover Ordner → Zettel/Kapitel (ohne Fenster, mit dem Stift bedienbar)
------------------------------------------------------------------------------
-- Basisordner aus lernordner.py (einmal erfragt); Pfad einer Notiz → Ordner, Unterordner, Name
local basis_cache = nil
local function basis_pfad()
  if not basis_cache then
    local e = erstes(helfer("konfig"), "BASIS")
    basis_cache = e and e[1] or ""
  end
  return basis_cache
end
local function pfad_teile(pfad)
  local b = basis_pfad()
  local rel = (b ~= "" and pfad:sub(1, #b + 1) == b .. "/") and pfad:sub(#b + 2) or nil
  local teile = {}
  if rel then for t in rel:gmatch("[^/]+") do teile[#teile + 1] = t end end
  if #teile == 3 then return teile[1], teile[2] end            -- Ordner / Unterordner / Datei
  if #teile == 2 then return teile[1], nil end
  return pfad:match("([^/]+)/[^/]+$") or "", nil               -- außerhalb der Basis: nur Elternordner
end

local OEFFNEN_SYMBOL = "lernordner-oeffnen-symbolic"
local oeffnen_pop = nil

lernOeffneDatei = im_hintergrund("lernOeffneDatei", function(pfad) wechsle_zu(pfad, nil) end)
lernOeffneKapitel = im_hintergrund("lernOeffneKapitel", function(teil, nr)
  local e = erstes(helfer("kapitel-neu", teil, nr), "OPEN")
  if e then wechsle_zu(e[1], nil) end
end)
lernNeuesKapitel = im_hintergrund("lernNeuesKapitel", function(teil, titel)
  local e = erstes(helfer("kapitel-titel", teil, titel), "OPEN")
  if e then wechsle_zu(e[1], nil) end
end)

-- Taste aus einem GdkEventKey (lgi: Feld direkt oder über .key)
local function taste(ev)
  local ok, k = pcall(function() return ev.keyval end)
  if ok and k then return k end
  ok, k = pcall(function() return ev.key.keyval end)
  return ok and k or nil
end

-- Vergleich für die Filterung beim Tippen (auch Umlaute: GLib.utf8_casefold)
local function falte(s)
  local g = glib()
  if g and g.utf8_casefold then
    local ok, r = pcall(g.utf8_casefold, s, -1)
    if ok and r then return r end
  end
  return s:lower()
end

local function baue_oeffnen(Gtk, anker)
  local aktuell = app.getDocumentStructure().xoppFilename
  local aktueller_ordner = (pfad_teile(aktuell))
  local pop = Gtk.Popover { relative_to = anker, position = Gtk.PositionType.RIGHT, modal = false }
  local stapel = Gtk.Stack { transition_type = Gtk.StackTransitionType.SLIDE_LEFT_RIGHT }

  local function zeile(text, aktion, fett, grau)
    local l = Gtk.Label { label = text, xalign = 0, ellipsize = 3, max_width_chars = 40 }  -- 3 = END
    if fett then l:set_markup("<b>" .. GLib_escape(text) .. "</b>") end
    if grau then l:set_markup("<span foreground='#8a8a8a'>" .. GLib_escape(text) .. "</span>") end
    local b = Gtk.Button { relief = Gtk.ReliefStyle.NONE, can_focus = false, height_request = 40 }
    b:add(l)
    function b:on_clicked() aktion() end
    return b
  end
  local function liste()
    local box = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 0 }
    local sw = Gtk.ScrolledWindow { hscrollbar_policy = Gtk.PolicyType.NEVER,
      min_content_height = 420, max_content_height = 520, propagate_natural_height = true }
    sw:add(box)
    return sw, box
  end

  -- Ebene 1: zuletzt geöffnet, dann Ordner
  local sw1, box1 = liste()
  local n = 0
  for _, p in ipairs(lies_verlauf()) do
    if p ~= aktuell and existiert(p) and not p:match("/%.papierkorb/") then
      if n == 0 then
        local k = Gtk.Label { xalign = 0, margin_start = 8, margin_top = 2 }
        k:set_markup("<small><span alpha='60%'>" .. T("Zuletzt", "Recent") .. "</span></small>")
        box1:add(k)
      end
      local name = p:match("([^/]+)%.xopp$") or p
      local ordner = p:match("([^/]+)/[^/]+$") or ""
      local b = zeile(name .. "   ·  " .. ordner, function() pop:popdown(); lernOeffneDatei(p) end)
      box1:add(b)
      n = n + 1
      if n >= 6 then break end
    end
  end
  if n > 0 then box1:add(Gtk.Separator { margin_top = 4, margin_bottom = 4 }) end
  -- Inhalt eines Ordners (oder "Ordner/Unterordner") als Seite im Stapel
  local aktueller_rel = (function()
    local o, u = pfad_teile(aktuell)
    return u and (o .. "/" .. u) or o
  end)()
  local zeige_inhalt
  zeige_inhalt = function(name, seite, zurueck)
        -- Ebene 2 frisch aufbauen
        local alt = stapel:get_child_by_name(seite)
        if alt then alt:destroy() end
        local sw2, box2 = liste()
        box2:add(zeile("‹  " .. name:match("([^/]+)$"), function() stapel:set_visible_child_name(zurueck) end, true))
        local eintraege = helfer("ablage", name)
        local kapitelzeilen = {}       -- { knopf, gefalteter Text } für die Filterung beim Tippen
        for _, x in ipairs(eintraege) do
          if x.key == "UNTER" then
            local u = name .. "/" .. x[1]
            local anzahl = tonumber(x[2]) or 0
            box2:add(zeile((u == aktueller_rel and "● " or "") .. "▸ " .. x[1] ..
              (anzahl > 0 and ("  (" .. anzahl .. ")") or "") .. "  ›", function()
              zeige_inhalt(u, "inhalt2", seite)
            end, u == aktueller_rel))
          elseif x.key == "TEIL" then
            -- „＋ Neues Kapitel“: Antippen → Eingabefeld; Tippen filtert die Liste,
            -- Enter legt an (Buchkapitel bei gleichem Titel, sonst nächste freie Nummer)
            local neu_stapel = Gtk.Stack {}
            local neu_knopf = zeile(T("＋  Neues Kapitel …", "＋  New chapter …"), function() end, true)
            local feld = Gtk.Entry { placeholder_text = T("Titel – Enter legt an", "Title – Enter creates it"), height_request = 40,
              margin_start = 6, margin_end = 6, activates_default = false }
            neu_stapel:add_named(neu_knopf, "knopf")
            neu_stapel:add_named(feld, "feld")
            function neu_knopf:on_clicked()
              neu_stapel:set_visible_child_name("feld")
              feld:grab_focus()
            end
            function feld:on_changed()
              local f = falte(feld:get_text():gsub("^%s+", ""):gsub("%s+$", ""))
              for _, k in ipairs(kapitelzeilen) do
                k[1]:set_visible(f == "" or k[2]:find(f, 1, true) ~= nil)
              end
            end
            function feld:on_activate()
              local titel = feld:get_text():gsub("^%s+", ""):gsub("%s+$", "")
              if titel == "" then return end
              pop:popdown()
              lernNeuesKapitel(name, titel)
            end
            function feld:on_key_press_event(ev)
              if taste(ev) == 0xff1b then                -- Escape: Feld zu, Filter weg
                feld:set_text("")
                neu_stapel:set_visible_child_name("knopf")
                return true
              end
              return false
            end
            box2:add(neu_stapel)
          elseif x.key == "KAPITEL" then
            local pfad, nr = x[2], x[3]
            local da = pfad ~= ""
            -- angelegt: ✓ ; noch nicht angelegt: grau mit „＋“ (Antippen legt das Heft an)
            local text = (pfad == aktuell and "● " or "") .. (da and "" or "＋ ") .. x[1] .. (da and "  ✓" or "")
            local b = zeile(text, function()
              pop:popdown()
              if da then lernOeffneDatei(pfad) else lernOeffneKapitel(name, nr) end
            end, false, not da)
            kapitelzeilen[#kapitelzeilen + 1] = { b, falte(x[1]) }
            box2:add(b)
          elseif x.key == "ZETTEL" then
            local pfad = x[2]
            box2:add(zeile((pfad == aktuell and "● " or "") .. x[1], function()
              pop:popdown(); lernOeffneDatei(pfad)
            end))
          end
        end
        stapel:add_named(sw2, seite)
        sw2:show_all()
        stapel:set_visible_child_name(seite)
  end

  for _, e in ipairs(helfer("ablage")) do
    if e.key == "ORDNER" then
      local name, anzahl = e[1], tonumber(e[2]) or 0
      local text = name .. (name == EINGANG() and anzahl > 0 and ("  (" .. anzahl .. ")") or "") .. "  ›"
      box1:add(zeile((name == aktueller_ordner and "● " or "") .. text, function()
        zeige_inhalt(name, "inhalt", "ordner")
      end, name == aktueller_ordner))
    end
  end
  -- Fußzeile: Seltenes
  local fuss = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 4, margin_top = 6 }
  local function klein(text, f)
    local b = Gtk.Button { label = text, relief = Gtk.ReliefStyle.NONE, can_focus = false }
    function b:on_clicked() pop:popdown(); f() end
    fuss:pack_start(b, true, true, 0)
  end
  klein(T("⌕ Tag-Suche", "⌕ Tag search"), function() lernSuche() end)
  klein(T("⇩ PDF importieren", "⇩ Import PDF"), function() lernPdf() end)
  local ebene1 = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, margin = 6 }
  ebene1:pack_start(sw1, true, true, 0)
  ebene1:pack_start(fuss, false, false, 0)
  stapel:add_named(ebene1, "ordner")
  pop:add(stapel)
  stapel:show_all()
  -- direkt im aktuellen Ordner beginnen? Nein: Übersicht zuerst, aktueller Ordner ist markiert.
  stapel:set_visible_child_name("ordner")
  return pop
end

function GLib_escape(s)
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

function lernOeffnen()
  local g = gtk()
  if not g then meldung(T("Für „Öffnen“ fehlt lua-lgi für Lua 5.4.", "“Open” needs lua-lgi for Lua 5.4.")); return end
  local ok, err = pcall(function()
    if oeffnen_pop then
      local war_offen = oeffnen_pop:get_visible()
      oeffnen_pop:destroy(); oeffnen_pop = nil
      if war_offen then return end              -- zweiter Tipp schließt
    end
    local anker = finde_knopf(g.Gtk, OEFFNEN_SYMBOL)
    if not anker then log("Öffnen-Knopf nicht gefunden"); return end
    oeffnen_pop = baue_oeffnen(g.Gtk, anker)
    oeffnen_pop:popup()
  end)
  if not ok then log("lernOeffnen:", tostring(err)) end
end


------------------------------------------------------------------------------
-- Etikett-Leiste (eigene Zeile unter der Werkzeugleiste, mittig):
--   [03] Chronische Erkrankungen / [064] Gicht · #tag #tag [Feld]  ✓ Fertig
-- Ablauf (nach ＋ oder Antippen eines Felds; Leiste ist dann farbig):
--   Ordner tippen/wählen → Name tippen/wählen (freie Kapitel) → Tags → Fertig.
--   Ordner/Name werden einmal übernommen, wenn man das Name-Feld verlässt.
-- Nummern stehen separat: Ordner "NN", Notizen in nummerierten Ordnern "NNN".
-- Tags stehen unsichtbar oberhalb der Seite (y < 0) als Text Sans 10 #808080;
-- #Wörter aus anderen Textfeldern der Seite erscheinen kursiv mit.
------------------------------------------------------------------------------
local TAG_X, TAG_Y = 0, -40
local E = nil                      -- Widgets und Zustand der Leiste
local letzte_verschiebung = nil    -- { von, nach, neuer_ordner }

local function trimme(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function esc(s) return GLib_escape(s) end
local function nr_markup(nr) return "<span alpha='55%' font_features='tnum'>" .. esc(nr) .. "</span>" end
local function ist_datumsname(t) return t:match("^%d%d%d%d%-%d%d%-%d%d") ~= nil end

local function ordner_teile(name)          -- "03 Chronische …" → "03", "Chronische …"
  local nr, rest = name:match("^(%d%d) (.+)$")
  if nr then return nr, rest end
  return nil, name
end
local function name_teile(stamm)           -- "064 Gicht" → "064", "Gicht"
  local nr, rest = stamm:match("^(%d%d%d) (.+)$")
  if nr then return nr, rest end
  return nil, stamm
end
local function nummerierter_ordner(name)
  local nr = ordner_teile(name)
  return nr ~= nil and nr ~= "00" and nr ~= "10" and nr ~= "99"
end

local function klasse(w, k, an)
  local c = w:get_style_context()
  if an then c:add_class(k) else c:remove_class(k) end
end

-- ---- Tags lesen/schreiben (aktuelle Seite) ---------------------------------
local function normiere_tag(w)
  w = w:gsub("^#+", ""):gsub("[%c%p]", function(c) return (c == "-" or c == "_") and c or "" end)
  local g = glib()
  if g and g.utf8_strdown then
    local ok, r = pcall(g.utf8_strdown, w, -1)
    if ok and r then w = r end
  else
    w = w:lower()
  end
  w = w:gsub("^[%d_%-]+", "")                 -- lerntags: Tag beginnt mit Buchstabe
  return w ~= "" and ("#" .. w) or nil
end

local function seiten_tags()
  -- eigene Tags (Tag-Zeile) und #Wörter aus anderen Textfeldern der aktuellen Seite
  local eigene, aus_text, gesehen = {}, {}, {}
  local zeile = nil
  for _, t in ipairs(app.getTexts("layer")) do
    if ist_tagzeile(t) then
      zeile = zeile or t
      for w in t.text:gmatch("%S+") do
        local n = normiere_tag(w)
        if n and not gesehen[n] then gesehen[n] = true; eigene[#eigene + 1] = n end
      end
    end
  end
  for _, t in ipairs(app.getTexts("layer")) do
    if not ist_tagzeile(t) then
      for w in t.text:gmatch("#([^%s#]+)") do
        local n = normiere_tag(w)
        if n and not gesehen[n] then gesehen[n] = true; aus_text[#aus_text + 1] = n end
      end
    end
  end
  return eigene, aus_text, zeile
end

-- Schreibt die Tag-Zeile der aktuellen Seite neu (unsichtbar über der Seite).
local function tagzeile_schreiben(liste)
  texteditor_beenden()
  local _, _, alt = seiten_tags()
  local neu = table.concat(liste, " ")
  if alt and alt.text == neu and alt.y < 0 then return false end
  if not alt and neu == "" then return false end
  if alt then
    app.addToSelection({ alt.ref })
    app.activateAction("delete")
  end
  if neu ~= "" then
    app.addTexts({ texts = { { text = neu, font = { name = SCHRIFT, size = TAG_GROESSE }, color = TAG_FARBE,
      x = TAG_X, y = TAG_Y } }, allowUndoRedoAction = "grouped" })
  end
  app.clearSelection()
  pcall(app.refreshPage)
  return true
end

-- Alte, sichtbare graue Tag-Zeilen: Platzhalter "#" weg, echte Tags nach oben (unsichtbar)
local function alte_tagzeile_umziehen()
  local eigene, _, zeile = seiten_tags()
  if zeile and zeile.y >= 0 then tagzeile_schreiben(eigene) return true end
  return false
end

-- ---- Verschieben/Umbenennen (Ablauf wie früher lernAblegen, ohne Dialoge) ----
local function verschiebe(pfad, ziel)
  if pfad == "" or app.getDocumentStructure().xoppFilename ~= pfad then return nil end
  local seite = app.getDocumentStructure().currentPage
  if not speichern_und_warten(pfad) then
    fehler("m_speichern_unbestaetigt")
    return nil
  end
  local k = helfer("kopiere", pfad, ziel)
  if not erstes(k, "NEU") then return nil end            -- Helfer hat den Fehler gemeldet
  app.openFile(ziel, seite, true)
  if app.getDocumentStructure().xoppFilename ~= ziel then
    fehler("m_kopie_nicht_offen")
    return nil
  end
  local muell = { "papierkorb" }
  for _, e in ipairs(k) do
    if e.key == "MUELL" then muell[#muell + 1] = e[1] end
  end
  if #muell > 1 then helfer(table.unpack(muell)) end
  return ziel
end

local tags_schreiben_jetzt   -- unten

local function hinweis(text, art, mit_rueck)
  if not E then return end
  E.info_text:set_markup(text)
  klasse(E.info, "lern-hinweis", art == "hinweis")
  E.info_rueck:set_visible(mit_rueck == true)
  E.info:show()
  E.info_nr = (E.info_nr or 0) + 1
  local nr = E.info_nr
  local GLib = glib()
  if GLib then
    GLib.timeout_add(GLib.PRIORITY_DEFAULT, mit_rueck and 8000 or 6000, function()
      if E and E.info_nr == nr then E.info:hide() end
      return false
    end)
  end
end

local aus_notiz_lesen, zeige_chips, unter_zeigen   -- unten

local function nach_ablauf()
  -- nach Verschieben (läuft noch im Ablauf): offene Tags in die nun geöffnete Notiz
  -- schreiben, Leiste auf den neuen Pfad setzen, Fokus zurück, falls der Ablauf weitergeht
  if not E then return end
  E.stand = nil
  if E.tags_offen and tags_schreiben_jetzt(true) and not E.modus then
    local ds = app.getDocumentStructure()
    if ds.xoppFilename ~= "" then app.activateAction("save") end
  end
  local tags = E.tags
  -- tippt man schon wieder im Ordner-/Namensfeld, nur den neuen Pfad merken, Eingabe lassen
  local im_feld = E.modus and (E.ordner_feld.is_focus or E.name_feld.is_focus)
  aus_notiz_lesen(not im_feld)
  if E.modus then
    E.tags = tags
    zeige_chips()
    if not im_feld then E.tag_feld:grab_focus_without_selecting() end
  end
end

-- neu angelegte Ordner wieder entfernen (innerster zuerst; os.remove löscht nur leere)
local function ordner_wegraeumen(liste)
  for i = #liste, 1, -1 do os.remove(liste[i]) end
end

lernAblage = im_hintergrund("lernAblage", function(ordnername, untername, titel)
  local pfad = app.getDocumentStructure().xoppFilename
  if pfad == "" then return end
  local neue = {}
  local o = erstes(helfer("ordner-neu", ordnername), "ORDNER")
  if not o then nach_ablauf() return end
  if o[2] == "NEU" then neue[#neue + 1] = o[1] end
  local ziel_ordner, anzeige = o[1], o[1]:match("([^/]+)$")
  if untername then
    local u = erstes(helfer("ordner-neu", untername, "--in", o[1]), "ORDNER")
    if not u then ordner_wegraeumen(neue) nach_ablauf() return end
    if u[2] == "NEU" then neue[#neue + 1] = u[1] end
    ziel_ordner, anzeige = u[1], anzeige .. " / " .. u[1]:match("([^/]+)$")
  end
  local z = helfer("ziel-name", pfad, ziel_ordner, titel)
  local ziel = erstes(z, "NAME")
  if erstes(z, "SELBST") or not ziel then
    ordner_wegraeumen(neue)                                 -- leere neue Ordner nicht stehen lassen
    nach_ablauf()
    return
  end
  local neu = verschiebe(pfad, ziel[1])
  if neu then
    letzte_verschiebung = { von = pfad, nach = neu, neue_ordner = neue }
    local text = (pfad:match("^(.*)/") == neu:match("^(.*)/")) and T("umbenannt", "renamed")
                 or ("→ " .. esc(anzeige))
    hinweis(text, "info", true)
  else
    ordner_wegraeumen(neue)
  end
  nach_ablauf()
end)

lernAblageRueckgaengig = im_hintergrund("lernAblageRueckgaengig", function()
  local v = letzte_verschiebung
  letzte_verschiebung = nil
  if E then E.info:hide() end
  if not v or app.getDocumentStructure().xoppFilename ~= v.nach then return end
  local z = erstes(helfer("zielname-stamm", v.nach, v.von:match("^(.*)/[^/]*$"), v.von:match("([^/]+)%.xopp$")), "NAME")
  if z and verschiebe(v.nach, z[1]) and v.neue_ordner then ordner_wegraeumen(v.neue_ordner) end
  nach_ablauf()
end)

-- ---- Vorschlagsliste unter einem Feld --------------------------------------
local function vorschlaege_zu()
  if E and E.pop then E.pop:popdown() end
  if E then E.vz, E.vz_index = nil, 0 end
end

-- ↓/↑ bewegt die Markierung in der Vorschlagsliste
local function vorschlag_markieren(schritt)
  if not E.vz or #E.vz == 0 then return false end
  local alt = E.vz_knoepfe[E.vz_index]
  if alt then klasse(alt, "lern-gewaehlt", false) end
  E.vz_index = math.max(1, math.min(#E.vz, E.vz_index + schritt))
  local b = E.vz_knoepfe[E.vz_index]
  klasse(b, "lern-gewaehlt", true)
  -- sichtbar halten
  local adj = E.pop_sw:get_vadjustment()
  local a = b:get_allocation()
  if a.y < adj.value then adj.value = a.y
  elseif a.y + a.height > adj.value + adj.page_size then adj.value = a.y + a.height - adj.page_size end
  return true
end

-- markierten Vorschlag übernehmen (true, wenn einer markiert war)
local function vorschlag_nehmen()
  if E.vz and E.vz_index > 0 and E.vz[E.vz_index] then
    E.vz[E.vz_index].aktion()
    return true
  end
  return false
end

-- zeilen = { { markup = "…", aktion = function() end }, … }
local function vorschlaege(anker, zeilen)
  if not E then return end
  local Gtk = E.Gtk
  if #zeilen == 0 then vorschlaege_zu() return end
  if E.pop and E.pop_anker ~= anker then
    E.pop:destroy()
    E.pop = nil
  end
  if not E.pop then
    E.pop = Gtk.Popover { position = Gtk.PositionType.BOTTOM, modal = false, relative_to = anker }
    pcall(function() E.pop.transitions_enabled = false end)
    E.pop_anker = anker
    E.pop_sw = Gtk.ScrolledWindow { hscrollbar_policy = Gtk.PolicyType.NEVER,
      max_content_height = 420, propagate_natural_height = true, propagate_natural_width = true }
    E.pop_box = Gtk.Box { orientation = Gtk.Orientation.VERTICAL, spacing = 0, margin = 4 }
    E.pop_sw:add(E.pop_box)
    E.pop:add(E.pop_sw)
  end
  E.pop:set_relative_to(anker)
  for _, c in ipairs(E.pop_box:get_children()) do c:destroy() end
  E.vz, E.vz_knoepfe, E.vz_index = zeilen, {}, 0
  for _, z in ipairs(zeilen) do
    local l = Gtk.Label { xalign = 0 }
    l:set_markup(z.markup)
    local b = Gtk.Button { relief = Gtk.ReliefStyle.NONE, can_focus = false, height_request = 38 }
    b:add(l)
    function b:on_clicked() z.aktion() end
    E.pop_box:add(b)
    E.vz_knoepfe[#E.vz_knoepfe + 1] = b
  end
  E.pop_sw:show_all()
  if not E.pop:get_visible() then E.pop:popup() end
  if not anker.is_focus then anker:grab_focus_without_selecting() end
end

-- ---- Daten für die Vorschläge -----------------------------------------------
local function lade_ordner()
  local liste, naechster = {}, "01"
  for _, e in ipairs(helfer("ablage")) do
    if e.key == "ORDNER" then
      local nr, rest = ordner_teile(e[1])
      liste[#liste + 1] = { name = e[1], nr = nr, rest = rest, f = falte(e[1]), f_rest = falte(rest) }
    elseif e.key == "NAECHSTER" then
      naechster = e[1]
    end
  end
  return liste, naechster
end

local function lade_ordnerinfo(wahl)
  -- wahl = { name = voller Ordnername (vorhanden) | nil, neu = true/false }
  local info = { nummeriert = false, naechste = "001", frei = {}, belegt = {}, buch = {},
                 unter = {}, naechster_unter = "01" }
  if wahl.neu then info.nummeriert = true return info end
  for _, x in ipairs(helfer("ablage", wahl.name)) do
    if x.key == "UNTER" then
      local nr, rest = ordner_teile(x[1])
      info.unter[#info.unter + 1] = { name = x[1], nr = nr, rest = rest, f = falte(x[1]), f_rest = falte(rest) }
    elseif x.key == "NAECHSTER_UNTER" then
      info.naechster_unter = x[1]
    elseif x.key == "NUMMERIERT" then
      info.nummeriert, info.naechste = true, x[1]
    elseif x.key == "KAPITEL" then
      local nr, titel = name_teile(x[1])
      local k = { nr = nr or "", titel = titel, f = falte(titel), pfad = x[2] }
      if x[2] == "" then info.frei[#info.frei + 1] = k else info.belegt[#info.belegt + 1] = k end
      if x[4] == "BUCH" and x[2] ~= "" then info.buch[x[2]] = true end
    end
  end
  return info
end

-- freie Kapitel aller Ordner (für die Suche im Namensfeld, solange noch kein Ordner gewählt ist)
local function lade_frei_alle()
  local liste = {}
  for _, e in ipairs(helfer("kapitel-frei")) do
    if e.key == "FREI" then
      local nr, rest = ordner_teile(e[1])
      liste[#liste + 1] = { ordner = e[1], onr = nr, orest = rest, nr = e[2], titel = e[3], f = falte(e[3]) }
    end
  end
  return liste
end

local function bekannte_tags()
  local jetzt = os.time()
  if not E.tag_cache or jetzt - E.tag_cache_zeit > 60 then
    E.tag_cache, E.tag_cache_zeit = {}, jetzt
    for _, e in ipairs(helfer("tags-liste")) do
      if e.key == "TAG" then E.tag_cache[#E.tag_cache + 1] = e[1] end
    end
  end
  return E.tag_cache
end

-- ---- Anzeige ------------------------------------------------------------------
local function zeige_nr(label, nr, neu)
  label:set_text(nr or "")
  label:set_visible(nr ~= nil and nr ~= "")
  klasse(label, "lern-nr-neu", neu == true)
end

zeige_chips = function()
  local Gtk = E.Gtk
  for _, c in ipairs(E.chips:get_children()) do c:destroy() end
  for i, t in ipairs(E.tags) do
    local box = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 0, valign = Gtk.Align.CENTER }
    klasse(box, "lern-chip", true)
    box:pack_start(Gtk.Label { label = t }, false, false, 0)
    local x = Gtk.Button { label = "×", relief = Gtk.ReliefStyle.NONE, can_focus = false }
    function x:on_clicked()
      table.remove(E.tags, i)
      zeige_chips()
      tags_schreiben_jetzt()
    end
    box:pack_start(x, false, false, 0)
    E.chips:pack_start(box, false, false, 0)
  end
  for _, t in ipairs(E.text_tags) do
    local l = Gtk.Label { label = t, valign = Gtk.Align.CENTER, tooltip_text = T("steht in einem Textfeld der Seite", "from a text box on the page") }
    klasse(l, "lern-chip-text", true)
    E.chips:pack_start(l, false, false, 0)
  end
  E.chips:show_all()
  klasse(E.tag_feld, "lern-ohne-tags", #E.tags == 0 and #E.text_tags == 0)
  E.tag_feld:set_placeholder_text((#E.tags == 0 and #E.text_tags == 0) and "#tags?" or "#")
end

-- Unterordner-Feld (dritte Ebene) nur zeigen, wenn es einen Unterordner gibt
unter_zeigen = function()
  if not E or not E.unter_feld then return end
  local da = E.unter ~= nil
  E.unter_feld:set_visible(da)
  E.unter_strich:set_visible(da)
  if da then
    if not E.unter_feld.is_focus then E.unter_feld:set_text(E.unter.rest) end
    zeige_nr(E.unter_nr, E.unter.nr, E.unter.neu)
  else
    E.unter_feld:set_text("")
    zeige_nr(E.unter_nr, nil)
  end
end

-- Ordnerinfo des obersten Ordners (für die Unterordner-Liste) und des Zielordners (für Namen)
local function eltern_info()
  if not E.elterninfo then
    E.elterninfo = E.wahl.neu and { unter = {}, naechster_unter = "01" } or lade_ordnerinfo(E.wahl)
  end
  return E.elterninfo
end
local function ziel_info()
  if E.unter then
    if E.unter.neu or E.wahl.neu then
      return { nummeriert = true, naechste = "001", frei = {}, belegt = {}, buch = {}, unter = {}, naechster_unter = "01" }
    end
    return lade_ordnerinfo({ name = E.wahl.name .. "/" .. E.unter.name })
  end
  return lade_ordnerinfo(E.wahl)
end

-- Unterordner aus Text: vorhandener (genau/eindeutig) oder neuer mit nächster Nummer
local function unter_aufloesen(text)
  text = trimme(text)
  local info, f, treffer = eltern_info(), falte(text), {}
  for _, u in ipairs(info.unter) do
    if u.f == f or u.f_rest == f then return { name = u.name, nr = u.nr, rest = u.rest, neu = false } end
    if u.f:find(f, 1, true) then treffer[#treffer + 1] = u end
  end
  if #treffer == 1 then
    local u = treffer[1]
    return { name = u.name, nr = u.nr, rest = u.rest, neu = false }
  end
  local nr, rest = ordner_teile(text)
  return { name = nil, nr = nr or info.naechster_unter, rest = rest, neu = true }
end

local function unter_setzen(u)
  E.unter = u
  E.ordnerinfo = nil
  unter_zeigen()
end

-- Unterordner nur in nummerierten (oder neuen) Ordnern; höchstens diese drei Ebenen
local function unterordner_erlaubt()
  return E.wahl.neu or nummerierter_ordner(E.wahl.name or "")
end

-- Zustand aus der geöffneten Notiz in die Leiste übernehmen
aus_notiz_lesen = function(felder)
  if felder == nil then felder = true end
  local ds = app.getDocumentStructure()
  local pfad = ds.xoppFilename
  local ordner, unter = pfad_teile(pfad)
  local stamm = pfad:match("([^/]+)%.xopp$") or pfad:match("([^/]+)$") or ""
  local onr, orest = ordner_teile(ordner)
  local nnr, nrest = name_teile(stamm)
  if not nummerierter_ordner(unter or ordner) then nnr, nrest = nil, stamm end
  E.start = { pfad = pfad, ordner = ordner, unter = unter, onr = onr, orest = orest, nnr = nnr, titel = nrest,
              seite = ds.currentPage }
  if felder then
    E.wahl = { name = ordner, nr = onr, rest = orest, neu = false }
    E.elterninfo, E.ordnerinfo = nil, nil
    E.unter = nil
    if unter then
      local unr, urest = ordner_teile(unter)
      E.unter = { name = unter, nr = unr, rest = urest, neu = false }
    end
    unter_zeigen()
    E.titel = nrest
    E.ordner_feld:set_text(pfad == "" and T("ohne Speicherort", "not saved yet") or orest)
    zeige_nr(E.ordner_nr, onr)
    E.name_feld:set_text(nrest)
    zeige_nr(E.name_nr, nnr)
  end
  local frei = pfad ~= ""
  E.ordner_feld:set_editable(frei); E.ordner_feld:set_can_focus(frei)
  E.name_feld:set_editable(frei);   E.name_feld:set_can_focus(frei)
  E.unter_feld:set_editable(frei);  E.unter_feld:set_can_focus(frei)
  local eigene, aus_text = seiten_tags()
  E.tags, E.text_tags = eigene, aus_text
  zeige_chips()
end

-- erzwingen: aus dem laufenden Ablauf heraus (nach dem Verschieben) trotzdem schreiben
tags_schreiben_jetzt = function(erzwingen)
  if beschaeftigt and not erzwingen then E.tags_offen = true return false end
  E.tags_offen = false
  local ok, err = pcall(tagzeile_schreiben, E.tags)
  if not ok then log("Tags schreiben:", tostring(err)) end
  E.stand = nil
  return ok and err
end

-- ---- Ablage-Modus -------------------------------------------------------------
local modus_aus   -- unten

local function modus_an()
  if E.modus then return end
  E.modus = true
  E.plus_wartet = false
  klasse(E.leiste, "lern-aktiv", true)
end

-- Ordner-Feld: Text → Wahl (genau / eindeutig / neu)
local function ordner_aufloesen(text)
  text = trimme(text)
  if text == "" or text == E.wahl.rest then return E.wahl end
  local f = falte(text)
  local treffer = {}
  for _, o in ipairs(E.ordnerliste) do
    if o.f == f or o.f_rest == f then return { name = o.name, nr = o.nr, rest = o.rest, neu = false } end
    if o.f:find(f, 1, true) then treffer[#treffer + 1] = o end
  end
  if #treffer == 1 then
    local o = treffer[1]
    return { name = o.name, nr = o.nr, rest = o.rest, neu = false }
  end
  local nr, rest = ordner_teile(text)
  return { name = nil, nr = nr or E.naechster_ordner, rest = rest, neu = true }
end

-- Ordner- und Namenswahl übernehmen (einmal, beim Verlassen von Ordner/Name)
local function ablage_uebernehmen(versuch)
  if not E.start or E.start.pfad == "" then return end
  -- noch fokussierte Felder zählen mit (z. B. „✓ Fertig“ direkt aus dem Namensfeld)
  if E.ordner_feld.is_focus then
    local w = ordner_aufloesen(E.ordner_feld:get_text())
    if w ~= E.wahl then E.wahl = w; E.ordnerinfo = nil end
  end
  if E.unter_feld.is_focus and E.unter and trimme(E.unter_feld:get_text()) ~= E.unter.rest then
    unter_setzen(unter_aufloesen(E.unter_feld:get_text()))
  end
  if E.name_feld.is_focus then E.titel = trimme(E.name_feld:get_text()) end
  if beschaeftigt then
    -- es läuft noch ein Ablauf (z. B. ＋ öffnet gerade das Blatt): gleich nochmal versuchen –
    -- aber höchstens ein wartender Versuch, sonst greifen gestapelte Versuche später erneut zu
    local GLib = glib()
    if GLib and not E.ablage_wartet and (versuch or 0) < 150 then
      E.ablage_wartet = true
      GLib.timeout_add(GLib.PRIORITY_DEFAULT, 200, function()
        E.ablage_wartet = false
        ablage_uebernehmen((versuch or 0) + 1)
        return false
      end)
    end
    return
  end
  -- Ist inzwischen eine andere Notiz offen (Öffnen, GNOME-Suche)? Dann gilt die Wahl nicht mehr.
  if app.getDocumentStructure().xoppFilename ~= E.start.pfad then
    E.stand = nil
    return
  end
  local titel = trimme(E.titel or "")
  if titel == "" then titel = E.start.titel end
  local gleicher_unter = (E.unter == nil and E.start.unter == nil)
    or (E.unter ~= nil and not E.unter.neu and E.unter.name == E.start.unter)
  local gleicher_ordner = (not E.wahl.neu) and E.wahl.name == E.start.ordner and gleicher_unter
  if gleicher_ordner and titel == E.start.titel then return end
  local unter = E.unter and (E.unter.neu and E.unter.rest or E.unter.name) or nil
  lernAblage(E.wahl.neu and E.wahl.rest or E.wahl.name, unter, titel)
end

local function fokus_zur_seite()
  if not E then return end
  if E.xournal then E.xournal:grab_focus() else E.fenster:set_focus(nil) end
end

modus_aus = function(uebernehmen)
  if not E.modus then return end
  E.modus = false
  E.plus_wartet = false
  vorschlaege_zu()
  klasse(E.leiste, "lern-aktiv", false)
  if uebernehmen then
    ablage_uebernehmen()
    local rest = trimme(E.tag_feld:get_text())
    if rest ~= "" then
      local n = normiere_tag(rest)
      if n then E.tags[#E.tags + 1] = n end
      tags_schreiben_jetzt()
    end
    E.tag_feld:set_text("")
    if not beschaeftigt then
      local ds = app.getDocumentStructure()
      if ds.xoppFilename ~= "" and not ist_leer(ds) then app.activateAction("save") end
    end
  else
    E.tag_feld:set_text("")
  end
  E.stand = nil
  fokus_zur_seite()
end

local function ordner_gewaehlt(w)
  if w.neu or w.name ~= E.wahl.name then E.unter = nil; E.elterninfo = nil; unter_zeigen() end
  E.wahl = w
  E.ordnerinfo = nil
  E.ordner_feld:set_text(w.rest)
  zeige_nr(E.ordner_nr, w.nr, w.neu)
  vorschlaege_zu()
  -- Name schon ordentlich (kein Datums-Name)? Dann gleich weiter zu den Tags.
  local t = trimme(E.name_feld:get_text())
  if t ~= "" and not ist_datumsname(t) then E.tag_feld:grab_focus() else E.name_feld:grab_focus() end
end

local function ordner_vorschlaege()
  local text = trimme(E.ordner_feld:get_text())
  local f = falte(text)
  local zeilen, genau = {}, false
  local alle = (text == "" or text == E.wahl.rest)
  for _, o in ipairs(E.ordnerliste) do
    if alle or o.f:find(f, 1, true) then
      if o.f == f or o.f_rest == f then genau = true end
      local akt = (o.name == E.start.ordner) and "● " or ""
      zeilen[#zeilen + 1] = { markup = akt .. (o.nr and (nr_markup(o.nr) .. "  ") or "") .. esc(o.rest),
        aktion = function() ordner_gewaehlt({ name = o.name, nr = o.nr, rest = o.rest, neu = false }) end }
    end
  end
  if not alle and not genau and text ~= "" then
    local w = ordner_aufloesen(text)
    if w.neu then
      table.insert(zeilen, 1, { markup = "＋ " .. nr_markup(w.nr) .. "  " .. esc(w.rest) .. "  <i>" .. T("neu", "new") .. "</i>",
        aktion = function() ordner_gewaehlt(w) end })
    end
  end
  -- Nummer daneben: was würde gewählt?
  if alle then zeige_nr(E.ordner_nr, E.wahl.nr, E.wahl.neu)
  else local w = ordner_aufloesen(text); zeige_nr(E.ordner_nr, w.nr, w.neu) end
  vorschlaege(E.ordner_feld, zeilen)
end

-- Name-Feld: Nummer-Vorschau und freie Kapitel
local function name_vorschau(text)
  local info = E.ordnerinfo
  text = trimme(text)
  if not info or not info.nummeriert or text == "" or ist_datumsname(text) then return nil, false end
  local gleicher_unter = (E.unter == nil and E.start.unter == nil)
    or (E.unter ~= nil and not E.unter.neu and E.unter.name == E.start.unter)
  if (not E.wahl.neu) and E.wahl.name == E.start.ordner and gleicher_unter and E.start.nnr then
    return E.start.nnr, false
  end
  local f = falte(text)
  for _, k in ipairs(info.frei) do
    if k.f == f then return k.nr, false end
  end
  return info.naechste, true
end

local name_gewaehlt   -- unten

-- Kapitel aus der ordnerübergreifenden Suche gewählt: passenden Ordner gleich mit wählen
local function kapitel_global_gewaehlt(k)
  E.wahl = { name = k.ordner, nr = k.onr, rest = k.orest, neu = false }
  E.unter = nil; E.elterninfo = nil; unter_zeigen()
  E.ordner_feld:set_text(k.orest)
  zeige_nr(E.ordner_nr, k.onr, false)
  E.ordnerinfo = { nummeriert = true, naechste = k.nr, frei = { k }, belegt = {}, buch = {} }
  name_gewaehlt(k.titel)
end

-- Sucht das Namensfeld gerade über alle Ordner? (noch kein nummerierter Ordner gewählt)
local function global_suche()
  return E.unter == nil and not (E.wahl.neu or nummerierter_ordner(E.wahl.name or ""))
end

name_gewaehlt = function(titel)
  if global_suche() and E.frei_alle then
    -- Enter auf einem Titel, der genau einem freien Kapitel entspricht → dieses Kapitel
    local f, treffer = falte(trimme(titel)), {}
    for _, k in ipairs(E.frei_alle) do if k.f == f then treffer[#treffer + 1] = k end end
    if #treffer == 1 then kapitel_global_gewaehlt(treffer[1]) return end
  end
  E.titel = titel
  E.name_feld:set_text(titel)
  local nr, neu = name_vorschau(titel)
  zeige_nr(E.name_nr, nr, neu)
  vorschlaege_zu()
  E.tag_feld:grab_focus()
end

local name_vorschlaege   -- (rekursiv aus den Unterordner-Zeilen)
name_vorschlaege = function()
  local text = trimme(E.name_feld:get_text())
  local nr, neu = name_vorschau(text)
  zeige_nr(E.name_nr, nr, neu)
  if global_suche() and E.frei_alle then
    -- Kapitel aus allen Ordnern; Auswahl setzt den Ordner mit (wie erst die Straße, dann die Stadt)
    local f = falte(text)
    local alle = text == "" or ist_datumsname(text) or text == E.start.titel
    local zeilen = {}
    for _, k in ipairs(E.frei_alle) do
      if alle or k.f:find(f, 1, true) then
        zeilen[#zeilen + 1] = { markup = nr_markup(k.nr) .. "  " .. esc(k.titel) ..
          "   <span alpha='45%'>" .. esc(k.ordner) .. "</span>",
          aktion = function() kapitel_global_gewaehlt(k) end }
        if #zeilen >= 60 then break end
      end
    end
    vorschlaege(E.name_feld, zeilen)
    return
  end
  local info = E.ordnerinfo
  if not info or not info.nummeriert then vorschlaege_zu() return end
  local unter_zeilen = {}
  if E.unter == nil and unterordner_erlaubt() then
    local fu = falte(text)
    for _, u in ipairs(eltern_info().unter) do
      if text == "" or ist_datumsname(text) or u.f:find(fu, 1, true) then
        unter_zeilen[#unter_zeilen + 1] = { markup = "▸ " .. nr_markup(u.nr or "") .. "  " .. esc(u.rest) .. "  /",
          aktion = function()
            unter_setzen({ name = u.name, nr = u.nr, rest = u.rest, neu = false })
            E.ordnerinfo = ziel_info()
            E.name_feld:set_text("")
            E.name_feld:grab_focus()
            name_vorschlaege()
          end }
      end
    end
  end
  -- Liste, wenn der Name noch nicht ordentlich nummeriert ist oder man tippt
  local unveraendert = text == E.start.titel and (not E.wahl.neu) and E.wahl.name == E.start.ordner
  local f = falte(text)
  local alle = text == "" or ist_datumsname(text) or unveraendert
  local zeilen, genau = {}, false
  for _, k in ipairs(info.frei) do
    if alle or k.f:find(f, 1, true) then
      if k.f == f then genau = true end
      zeilen[#zeilen + 1] = { markup = nr_markup(k.nr) .. "  " .. esc(k.titel),
        aktion = function() name_gewaehlt(k.titel) end }
    end
  end
  for _, k in ipairs(info.belegt) do
    if k.f == f and text ~= "" then
      table.insert(zeilen, 1, { markup = "<i>" .. esc(k.titel) .. T(" gibt es hier schon (", " already exists here (") .. esc(k.nr) .. ")</i>",
        aktion = function() end })
      genau = true
    end
  end
  if not alle and not genau and text ~= "" then
    table.insert(zeilen, 1, { markup = "＋ " .. nr_markup(info.naechste) .. "  " .. esc(text) .. "  <i>" .. T("neu", "new") .. "</i>",
      aktion = function() name_gewaehlt(text) end })
  end
  for i = #unter_zeilen, 1, -1 do table.insert(zeilen, 1, unter_zeilen[i]) end
  vorschlaege(E.name_feld, zeilen)
end

-- Tag-Feld
local function tag_dazu(w)
  local n = normiere_tag(w)
  if not n then return end
  for _, t in ipairs(E.tags) do if t == n then return end end
  E.tags[#E.tags + 1] = n
  zeige_chips()
  tags_schreiben_jetzt()
end

local function tag_vorschlaege()
  local text = trimme(E.tag_feld:get_text())
  if text == "" then vorschlaege_zu() return end
  local f = falte("#" .. text:gsub("^#+", ""))
  local schon = {}
  for _, t in ipairs(E.tags) do schon[t] = true end
  local zeilen = {}
  for _, t in ipairs(bekannte_tags()) do
    if not schon[t] and falte(t):sub(1, #f) == f then
      zeilen[#zeilen + 1] = { markup = esc(t), aktion = function()
        E.tag_feld:set_text(""); tag_dazu(t); vorschlaege_zu() end }
      if #zeilen >= 8 then break end
    end
  end
  vorschlaege(E.tag_feld, zeilen)
end

-- ---- Neue Seite (grünes ＋ unten) ------------------------------------------
local function neue_seite()
  if E.modus then modus_aus(true) end
  E.erinnert = nil
  app.activateAction("new-page-at-end")
end

-- Notiz verwerfen (Papierkorb statt endgültig löschen): erst fragen, dann ein frisches Blatt öffnen
-- (app.openFile(…, true) verwirft die ungespeicherten Änderungen der alten Notiz), danach erst die Datei
-- der alten Notiz in .papierkorb legen – scheitert das Öffnen, bleibt alles wie es war.
function lernVerwerfen()
  local aktuell = app.getDocumentStructure().xoppFilename
  if aktuell == "" or not existiert(aktuell) then return end
  if not erstes(helfer("verwerfen", aktuell), "JA") then return end
  if app.getDocumentStructure().xoppFilename ~= aktuell then return end    -- inzwischen andere Notiz offen
  local e = erstes(helfer("neu-eingang"), "OPEN")
  if not e then return end
  app.openFile(e[1], 1, true)
  if app.getDocumentStructure().xoppFilename ~= e[1] then return end
  helfer("papierkorb", aktuell)
  local GLib = glib()
  if GLib and etikett_ablage_starten then
    GLib.idle_add(GLib.PRIORITY_DEFAULT_IDLE, function() pcall(etikett_ablage_starten) return false end)
  end
end
-- Schalter: soll die Leiste (und ggf. das Dock) der Drehung des Bildschirms folgen?
function lernDrehen()
  local e = erstes(helfer("drehen", "umschalten"), "DREHEN")
  local an = e and e[1] == "an"
  leiste.wunsch = nil                                                -- neu bewerten
  pcall(drehen_symbol)
  if E and E.info_text then
    hinweis(an and T("Leiste folgt der Drehung: an", "Toolbar follows rotation: on")
               or T("Leiste folgt der Drehung: aus", "Toolbar follows rotation: off"), "hinweis", false)
  end
end
function lernNeueSeite()
  if beschaeftigt or not E then return end
  local ds = app.getDocumentStructure()
  local schluessel = ds.xoppFilename .. "|" .. tostring(ds.currentPage)
  local eigene, aus_text = seiten_tags()
  if E.modus and E.plus_wartet then neue_seite() return end
  if #eigene == 0 and #aus_text == 0 and E.erinnert ~= schluessel and not ist_leer(ds) then
    -- Erinnerung: erst Tags für diese Seite (zweites ＋ oder Enter im leeren Feld = trotzdem weiter)
    E.erinnert = schluessel
    E.tag_feld:grab_focus()
    E.plus_wartet = true
    hinweis(T("Noch keine Tags auf dieser Seite – Enter oder ＋ = neue Seite",
              "No tags on this page yet – Enter or ＋ = new page"), "hinweis", false)
    return
  end
  neue_seite()
end

-- ---- Ablauf starten (von ＋ Neu) ---------------------------------------------
local function feld_mit_liste(feld)
  feld:grab_focus()
  -- GTK meldet focus-in nur bei aktivem Fenster; kam keine Meldung, das Betreten selbst ausführen
  if not E.modus and E.betreten and E.betreten[feld] then pcall(E.betreten[feld]) end
  local GLib = glib()
  if not GLib then return end
  -- falls Xournal den Fokus danach noch einmal zur Seite holt: nachfassen
  GLib.timeout_add(GLib.PRIORITY_DEFAULT, 300, function()
    if not E.modus then feld:grab_focus() end
    if feld.is_focus and not (E.pop and E.pop:get_visible()) then
      if feld == E.ordner_feld then ordner_vorschlaege()
      elseif feld == E.name_feld then name_vorschlaege() end
    end
    return false
  end)
end

function etikett_ablage_starten()
  if not E then return end
  E.stand = nil
  aus_notiz_lesen()
  -- erstes noch nicht geändertes Feld: Name (noch Datum; sucht Kapitel aller Ordner und wählt den
  -- Ordner mit) → Ordner (noch im Eingang) → Tags. Rücktaste im leeren Feld springt zurück.
  if not E.ordner_feld:get_can_focus() then feld_mit_liste(E.tag_feld)
  elseif ist_datumsname(E.start.titel) then feld_mit_liste(E.name_feld)
  elseif E.start.ordner == EINGANG() then feld_mit_liste(E.ordner_feld)
  else feld_mit_liste(E.tag_feld) end
end

-- ---- Aktualisieren (jede Sekunde, nicht während des Ablaufs) -----------------
local etikett_takt = 0
local function etikett_aktualisieren()
  if not E then return true end
  etikett_takt = etikett_takt + 1
  if etikett_takt % 5 == 0 and E.pfeile_weg then pcall(E.pfeile_weg) end   -- nach Neuaufbau der Leiste
  if E.art_markieren and E.plus:get_visible() then pcall(E.art_markieren) end
  if E.feldbreite_pruefen then pcall(E.feldbreite_pruefen) end
  local ok, err = pcall(function()
    if E.modus or beschaeftigt then return end
    if E.ordner_feld.is_focus or E.unter_feld.is_focus or E.name_feld.is_focus or E.tag_feld.is_focus then return end
    if app.getActionState("select-tool") ~= app.C.Tool_text then
      if alte_tagzeile_umziehen() then E.stand = nil end
    end
    local ds = app.getDocumentStructure()
    local eigene, aus_text = seiten_tags()
    local stand = ds.xoppFilename .. "|" .. tostring(ds.currentPage) .. "|" ..
                  table.concat(eigene, " ") .. "|" .. table.concat(aus_text, " ")
    if stand == E.stand then return end
    E.stand = stand
    aus_notiz_lesen()
  end)
  if not ok then log("Etikett aktualisieren:", tostring(err)) end
  return true
end

-- ---- Aufbau -------------------------------------------------------------------
local CSS = [[
.lern-leiste { margin: 1px 0; }
.lern-rahmen, .lern-rahmen viewport { background: transparent; border: none; box-shadow: none; }
.lern-leiste entry { background: transparent; background-image: none; border: none; box-shadow: none;
                     border-bottom: 2px solid transparent; border-radius: 0; min-height: 28px; padding: 0 3px; }
.lern-leiste entry:focus { border-bottom-color: @theme_selected_bg_color; }
.lern-leiste entry.lern-ohne-tags { background-color: rgba(229, 165, 10, 0.16); border-radius: 6px; }
.lern-nr { color: alpha(@theme_fg_color, 0.5); font-feature-settings: "tnum"; padding: 0; margin: 0 1px 0 3px; }
.lern-nr.lern-nr-neu { color: #1a7f37; }
.lern-chip { background-color: rgba(46, 160, 67, 0.18); border-radius: 12px; padding: 0 0 0 9px; }
.lern-chip button { min-height: 0; min-width: 0; padding: 0 6px; }
.lern-chip-text { background-color: alpha(@theme_fg_color, 0.07); border-radius: 12px; padding: 3px 9px; font-style: italic; }
.lern-info { background-color: rgba(53, 132, 228, 0.16); border-radius: 12px; padding: 0 2px 0 10px; }
.lern-info.lern-hinweis { background-color: rgba(229, 165, 10, 0.25); }
.lern-info button { padding: 0 8px; min-height: 0; }
.lern-gewaehlt { background-color: alpha(@theme_selected_bg_color, 0.3); }
.lern-seite-plus { background-image: none; background-color: #2ea043; color: white; border-radius: 26px;
                   min-width: 52px; min-height: 52px; font-size: 24px; padding: 0; border: none; }
.lern-seite-plus:hover { background-color: #3fb950; }
.lern-unten { background-color: alpha(@theme_bg_color, 0.92); border-radius: 30px; padding: 3px 4px 3px 10px;
              box-shadow: 0 1px 4px alpha(black, 0.25); }
.lern-unten button.lern-gewaehlt { background-color: alpha(@theme_selected_bg_color, 0.35); }
]]

etikett_einhaengen = function(fenster)
  local g = gtk()
  if not g then return false end
  local Gtk = g.Gtk
  local function suche(w, pruef)
    if pruef(w) then return w end
    if Gtk.Container:is_type_of(w) then
      for _, c in ipairs(w:get_children()) do
        local r = suche(c, pruef)
        if r then return r end
      end
    end
    return nil
  end
  local overlay = suche(fenster, function(w) return Gtk.Overlay:is_type_of(w) end)   -- "mainOverlay"
  if not overlay then log("Etikett-Leiste: kein GtkOverlay gefunden"); return false end
  local hauptbox = overlay:get_child()                                             -- "mainBox"
  if not (hauptbox and Gtk.Box:is_type_of(hauptbox)) then log("Etikett-Leiste: mainBox fehlt"); return false end
  local xournal = suche(fenster, function(w) return w:get_name() == "GtkXournal" end)

  local css = Gtk.CssProvider()
  css:load_from_data(CSS)
  Gtk.StyleContext.add_provider_for_screen(fenster:get_screen(), css, 600)

  -- Zwei gleich breite Hälften: links Ordner / Name (rechtsbündig), rechts Tags (linksbündig).
  -- So bleibt die Mitte fest, neue Tag-Kästchen wachsen nur nach rechts.
  local leiste = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, homogeneous = true }
  klasse(leiste, "lern-leiste", true)
  local links = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 2, halign = Gtk.Align.END }
  local rechts = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 4, halign = Gtk.Align.START }
  leiste:pack_start(links, true, true, 0)
  leiste:pack_start(rechts, true, true, 0)
  local function nr_label() local l = Gtk.Label { valign = Gtk.Align.CENTER }; klasse(l, "lern-nr", true); return l end
  local ordner_nr, name_nr, unter_nr = nr_label(), nr_label(), nr_label()
  local unter_feld = Gtk.Entry { width_chars = 14, placeholder_text = T("Unterordner", "Subfolder") }
  local unter_strich = Gtk.Label { label = "/" }
  local ordner_feld = Gtk.Entry { width_chars = 20, placeholder_text = T("Ordner", "Folder"), xalign = 1 }
  local name_feld = Gtk.Entry { width_chars = 24, placeholder_text = "Name" }
  local chips = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 3 }
  local tag_feld = Gtk.Entry { width_chars = 9, placeholder_text = "#tags?" }
  local info = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 2, valign = Gtk.Align.CENTER }
  klasse(info, "lern-info", true)
  local info_text = Gtk.Label {}
  local info_rueck = Gtk.Button { label = T("↶ Rückgängig", "↶ Undo"), relief = Gtk.ReliefStyle.NONE, can_focus = false }
  info:pack_start(info_text, false, false, 0)
  info:pack_start(info_rueck, false, false, 0)

  links:pack_start(ordner_nr, false, false, 0)
  links:pack_start(ordner_feld, false, false, 0)
  links:pack_start(Gtk.Label { label = "/" }, false, false, 2)
  links:pack_start(unter_nr, false, false, 0)
  links:pack_start(unter_feld, false, false, 0)
  links:pack_start(unter_strich, false, false, 2)
  links:pack_start(name_nr, false, false, 0)
  links:pack_start(name_feld, false, false, 0)
  rechts:pack_start(Gtk.Label { label = "·" }, false, false, 4)
  rechts:pack_start(chips, false, false, 0)
  rechts:pack_start(tag_feld, false, false, 0)
  rechts:pack_start(info, false, false, 6)

  E = { Gtk = Gtk, fenster = fenster, xournal = xournal, leiste = leiste, ordner_nr = ordner_nr, name_nr = name_nr,
        ordner_feld = ordner_feld, name_feld = name_feld, chips = chips, tag_feld = tag_feld,
        unter_nr = unter_nr, unter_feld = unter_feld, unter_strich = unter_strich,
        info = info, info_text = info_text, info_rueck = info_rueck, tags = {}, text_tags = {},
        modus = false, ordnerliste = {}, naechster_ordner = "01" }

  -- Fokus-Wechsel: erst kurz warten, wohin der Fokus geht
  local GLib = glib()
  local function spaeter(f) if GLib then GLib.timeout_add(GLib.PRIORITY_DEFAULT, 120, function() f() return false end) else f() end end
  local function irgendein_feld()
    return ordner_feld.is_focus or unter_feld.is_focus or name_feld.is_focus or tag_feld.is_focus
  end

  -- Ordner
  local function ordner_betreten()
    modus_an()
    E.ordnerliste, E.naechster_ordner = lade_ordner()
    ordner_vorschlaege()
  end
  function ordner_feld:on_focus_in_event() ordner_betreten() return false end
  function ordner_feld:on_changed() if ordner_feld.is_focus then ordner_vorschlaege() end end
  function ordner_feld:on_activate()
    if vorschlag_nehmen() then return end
    ordner_gewaehlt(ordner_aufloesen(ordner_feld:get_text()))
  end
  function ordner_feld:on_focus_out_event()
    local w = ordner_aufloesen(ordner_feld:get_text())
    if w ~= E.wahl then E.wahl = w; E.ordnerinfo = nil; ordner_feld:set_text(w.rest); zeige_nr(ordner_nr, w.nr, w.neu) end
    spaeter(function()
      if tag_feld.is_focus and not name_feld.is_focus then ablage_uebernehmen()   -- Name übersprungen
      elseif not irgendein_feld() and E.modus then modus_aus(true) end
    end)
    return false
  end
  -- Name
  local function name_betreten()
    modus_an()
    if not E.ordnerinfo then E.ordnerinfo = ziel_info() end
    if global_suche() then E.frei_alle = lade_frei_alle() end
    name_vorschlaege()
  end
  function name_feld:on_focus_in_event() name_betreten() return false end
  local name_intern = false
  function name_feld:on_changed()
    if name_intern then return end
    local text = name_feld:get_text()
    local pos = text:find("/", 1, true)
    if pos then
      -- "/" im Namen: das Getippte davor wird zum Unterordner (höchstens drei Ebenen)
      local vor, nach = trimme(text:sub(1, pos - 1)), trimme(text:sub(pos + 1):gsub("/", ""))
      name_intern = true; name_feld:set_text(nach); name_feld:set_position(-1); name_intern = false
      if E.unter then
        hinweis(T("Mehr als drei Ebenen gibt es nicht", "No more than three levels"), "hinweis", false)
      elseif not unterordner_erlaubt() then
        hinweis(T("Unterordner nur in nummerierten Ordnern – erst einen Ordner wählen",
                  "Subfolders only in numbered folders – choose a folder first"), "hinweis", false)
      elseif vor ~= "" then
        unter_setzen(unter_aufloesen(vor))
        E.ordnerinfo = ziel_info()
      end
    end
    if name_feld.is_focus then
      if not E.ordnerinfo then E.ordnerinfo = ziel_info() end
      name_vorschlaege()
    end
  end
  function name_feld:on_activate()
    if vorschlag_nehmen() then return end
    name_gewaehlt(trimme(name_feld:get_text()))
  end
  function name_feld:on_focus_out_event()
    E.titel = trimme(name_feld:get_text())
    spaeter(function()
      if ordner_feld.is_focus or unter_feld.is_focus or name_feld.is_focus then return end
      if tag_feld.is_focus then ablage_uebernehmen()          -- weiter zu den Tags: jetzt ablegen
      elseif E.modus then modus_aus(true) end
    end)
    return false
  end
  -- Unterordner (dritte Ebene)
  local function unter_vorschlaege()
    local text = trimme(unter_feld:get_text())
    local f, zeilen, genau = falte(text), {}, false
    local alle = text == "" or (E.unter and text == E.unter.rest)
    for _, u in ipairs(eltern_info().unter) do
      if alle or u.f:find(f, 1, true) then
        if u.f == f or u.f_rest == f then genau = true end
        zeilen[#zeilen + 1] = { markup = nr_markup(u.nr or "") .. "  " .. esc(u.rest), aktion = function()
          unter_setzen({ name = u.name, nr = u.nr, rest = u.rest, neu = false })
          vorschlaege_zu(); name_feld:grab_focus()
        end }
      end
    end
    if not alle and not genau and text ~= "" then
      local u = unter_aufloesen(text)
      if u.neu then
        table.insert(zeilen, 1, { markup = "＋ " .. nr_markup(u.nr) .. "  " .. esc(u.rest) .. "  <i>" .. T("neu", "new") .. "</i>",
          aktion = function() unter_setzen(u); vorschlaege_zu(); name_feld:grab_focus() end })
      end
    end
    vorschlaege(unter_feld, zeilen)
  end
  function unter_feld:on_focus_in_event()
    modus_an()
    unter_vorschlaege()
    return false
  end
  function unter_feld:on_changed() if unter_feld.is_focus then unter_vorschlaege() end end
  function unter_feld:on_activate()
    if vorschlag_nehmen() then return end
    local text = trimme(unter_feld:get_text())
    if text ~= "" then unter_setzen(unter_aufloesen(text)) end
    vorschlaege_zu()
    name_feld:grab_focus()
  end
  function unter_feld:on_focus_out_event()
    local text = trimme(unter_feld:get_text())
    if E.unter and text ~= "" and text ~= E.unter.rest then unter_setzen(unter_aufloesen(text)) end
    spaeter(function()
      if ordner_feld.is_focus or unter_feld.is_focus or name_feld.is_focus then return end
      if tag_feld.is_focus then ablage_uebernehmen()
      elseif E.modus then modus_aus(true) end
    end)
    return false
  end

  -- Tags
  local tag_intern = false
  local function tag_betreten()
    modus_an()
    vorschlaege_zu()
  end
  function tag_feld:on_focus_in_event() tag_betreten() return false end
  E.betreten = { [ordner_feld] = ordner_betreten, [name_feld] = name_betreten, [tag_feld] = tag_betreten }
  function tag_feld:on_changed()
    if tag_intern then return end
    local text = tag_feld:get_text()
    if text:find("[%s,;]") then
      local rest = text:match("[^%s,;]*$")
      for w in text:sub(1, #text - #rest):gmatch("[^%s,;]+") do tag_dazu(w) end
      tag_intern = true; tag_feld:set_text(rest); tag_feld:set_position(-1); tag_intern = false
    end
    tag_vorschlaege()
  end
  function tag_feld:on_activate()
    if vorschlag_nehmen() then return end
    local text = trimme(tag_feld:get_text())
    if text ~= "" then
      tag_intern = true; tag_feld:set_text(""); tag_intern = false
      tag_dazu(text)
      vorschlaege_zu()
      return
    end
    if E.plus_wartet then neue_seite() else modus_aus(true) end
  end
  function tag_feld:on_focus_out_event()
    spaeter(function()
      if not irgendein_feld() and E.modus then modus_aus(true) end
    end)
    return false
  end

  local function taste_gedrueckt(feld, ev)
    local k = taste(ev)
    if k == 0xff1b then                                         -- Escape: nichts übernehmen
      E.stand = nil
      modus_aus(false)
      aus_notiz_lesen()
      return true
    end
    if k == 0xff54 then return vorschlag_markieren(1) end         -- ↓
    if k == 0xff52 then return vorschlag_markieren(-1) end        -- ↑
    if k == 0xff53 and feld:get_position() >= feld:get_text_length() then   -- → am Textende: übernehmen, weiter
      if vorschlag_nehmen() then return true end
      if feld ~= tag_feld or trimme(feld:get_text()) ~= "" then feld:activate() return true end
      return false
    end
    if k == 0xff08 and feld == tag_feld and tag_feld:get_text() == "" and #E.tags > 0 then   -- Rücktaste
      table.remove(E.tags)
      zeige_chips()
      tags_schreiben_jetzt()
      return true
    end
    -- Rücktaste im leeren Feld: zurück ins vorige Feld (Tags → Name → Ordner), Cursor ans Ende
    if k == 0xff08 and feld == unter_feld and feld:get_text() == "" then
      unter_setzen(nil)                                        -- Unterordner-Ebene weg
      ordner_feld:grab_focus_without_selecting()
      ordner_feld:set_position(-1)
      return true
    end
    local zurueck = (feld == name_feld and (E.unter and unter_feld or ordner_feld))
                    or (feld == tag_feld and name_feld) or nil
    if k == 0xff08 and zurueck and feld:get_text() == "" and zurueck:get_can_focus() then
      zurueck:grab_focus_without_selecting()
      zurueck:set_position(-1)
      return true
    end
    return false
  end
  function ordner_feld:on_key_press_event(ev) return taste_gedrueckt(ordner_feld, ev) end
  -- Ordner und Name nicht mit dem Stift (versehentlich beim Schreiben), nur Finger/Maus
  local function vom_stift(ev)
    local ok, quelle = pcall(function() return ev:get_source_device():get_source() end)
    return ok and (quelle == "PEN" or quelle == "ERASER")
  end
  function ordner_feld:on_button_press_event(ev) return vom_stift(ev) end
  function name_feld:on_button_press_event(ev) return vom_stift(ev) end
  function name_feld:on_key_press_event(ev) return taste_gedrueckt(name_feld, ev) end
  function unter_feld:on_key_press_event(ev) return taste_gedrueckt(unter_feld, ev) end
  function unter_feld:on_button_press_event(ev) return vom_stift(ev) end
  function tag_feld:on_key_press_event(ev) return taste_gedrueckt(tag_feld, ev) end

  function info_rueck:on_clicked() lernAblageRueckgaengig() end

  -- Tippen/Schreiben auf der Seite beendet den Ablauf (Fang-Phase am Fenster, nur Klicks)
  local geste = Gtk.GestureMultiPress { widget = fenster, button = 0 }
  geste:set_propagation_phase(Gtk.PropagationPhase.CAPTURE)
  local function innen(w, x, y)
    if not w or not w:get_visible() then return false end
    local ok, wx, wy = fenster:translate_coordinates(w, math.floor(x), math.floor(y))
    return ok and wx >= 0 and wy >= 0 and wx < w:get_allocated_width() and wy < w:get_allocated_height()
  end
  function geste:on_pressed(_, x, y)
    if not E.modus then return end
    if innen(E.pop, x, y) or innen(E.plus, x, y) then return end
    if E.xournal and innen(E.xournal, x, y) then modus_aus(true) end
  end
  E.geste = geste                                               -- Referenz halten (GTK3 hält sie nicht)

  -- Unten mittig am Ende des Dokuments: Seitenart der aktuellen Seite (neue Seiten übernehmen sie,
  -- copyLastPageSettings) und grünes ＋ für eine neue Seite
  local unten = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 2, halign = Gtk.Align.CENTER,
    valign = Gtk.Align.END, margin_bottom = 18 }
  klasse(unten, "lern-unten", true)
  local ARTEN = { { "lined", T("liniert", "lined") }, { "graph", T("kariert", "squared") },
                  { "dotted", T("Punkte", "dotted") }, { "plain", T("leer", "plain") } }
  E.art_knoepfe = {}
  for _, a in ipairs(ARTEN) do
    local art = a[1]
    local bild = Gtk.DrawingArea { width_request = 26, height_request = 34 }
    function bild:on_draw(cr)
      local x, y, w, h = 2, 2, 22, 30
      cr:set_source_rgb(1, 1, 1); cr:rectangle(x, y, w, h); cr:fill()
      cr:set_line_width(1)
      cr:set_source_rgb(0.55, 0.65, 0.85)
      if art == "lined" then
        for yy = y + 7, y + h - 3, 5 do cr:move_to(x + 2, yy + 0.5); cr:line_to(x + w - 2, yy + 0.5) end
        cr:stroke()
        cr:set_source_rgb(0.9, 0.45, 0.45); cr:move_to(x + 6.5, y + 1); cr:line_to(x + 6.5, y + h - 1); cr:stroke()
      elseif art == "graph" then
        for yy = y + 4, y + h - 1, 4 do cr:move_to(x + 1, yy + 0.5); cr:line_to(x + w - 1, yy + 0.5) end
        for xx = x + 4, x + w - 1, 4 do cr:move_to(xx + 0.5, y + 1); cr:line_to(xx + 0.5, y + h - 1) end
        cr:stroke()
      elseif art == "dotted" then
        for yy = y + 4, y + h - 2, 4 do
          for xx = x + 4, x + w - 2, 4 do cr:rectangle(xx, yy, 1.3, 1.3) end
        end
        cr:fill()
      end
      cr:set_source_rgb(0.6, 0.6, 0.6); cr:rectangle(x + 0.5, y + 0.5, w - 1, h - 1); cr:stroke()
      return true
    end
    local b = Gtk.Button { relief = Gtk.ReliefStyle.NONE, can_focus = false, tooltip_text = T("Seite ", "Page ") .. a[2] }
    b:add(bild)
    function b:on_clicked()
      local ds = app.getDocumentStructure()
      local p = ds.pages[ds.currentPage]
      if p and p.pdfBackgroundPageNo and p.pdfBackgroundPageNo > 0 then
        hinweis(T("PDF-Seiten behalten ihren Hintergrund", "PDF pages keep their background"), "hinweis", false)
        return
      end
      local ok, err = pcall(app.changeCurrentPageBackground, art)
      if not ok then log("Seitenart:", tostring(err)) end
      E.art_stand = nil
    end
    unten:pack_start(b, false, false, 0)
    E.art_knoepfe[art] = b
  end
  local plus = Gtk.Button { label = "＋", can_focus = false, tooltip_text = T("Neue Seite", "New page"), margin_start = 8 }
  klasse(plus, "lern-seite-plus", true)
  function plus:on_clicked() lernNeueSeite() end
  unten:pack_start(plus, false, false, 0)
  overlay:add_overlay(unten)
  E.plus = unten
  E.art_markieren = function()
    local ds = app.getDocumentStructure()
    local p = ds.pages[ds.currentPage]
    local art = p and p.pageTypeFormat or ""
    if art == "ruled" then art = "lined" end
    if art == E.art_stand then return end
    E.art_stand = art
    for k, b in pairs(E.art_knoepfe) do klasse(b, "lern-gewaehlt", k == art) end
  end

  -- Fensterknöpfe ganz rechts in der Etikett-Zeile (die Fensterleiste ist ausgeblendet).
  -- Kein Vollbild: dort verliert GNOME 50 den Stift (siehe CLAUDE.md).
  local fk = Gtk.Box { orientation = Gtk.Orientation.HORIZONTAL, spacing = 0, halign = Gtk.Align.END,
    valign = Gtk.Align.CENTER, margin_end = 4 }
  local function fknopf(symbol, tipp, f)
    local b = Gtk.Button { relief = Gtk.ReliefStyle.NONE, can_focus = false, tooltip_text = tipp }
    b:add(Gtk.Image { icon_name = symbol, icon_size = Gtk.IconSize.BUTTON })
    function b:on_clicked() f() end
    fk:pack_start(b, false, false, 0)
    return b
  end
  fknopf("window-minimize-symbolic", T("Minimieren", "Minimise"), function() fenster:iconify() end)
  local maxi = fknopf("window-maximize-symbolic", T("Maximieren", "Maximise"), function()
    if fenster.is_maximized then fenster:unmaximize() else fenster:maximize() end
  end)
  fknopf("window-close-symbolic", T("Schließen", "Close"), function() fenster:close() end)
  local function maxi_symbol()
    maxi:get_child():set_from_icon_name(fenster.is_maximized and "window-restore-symbolic" or "window-maximize-symbolic",
      Gtk.IconSize.BUTTON)
  end
  fenster.on_notify["is-maximized"] = maxi_symbol
  maxi_symbol()
  -- Die Leiste darf das Fenster nicht breiter machen als den Bildschirm (Hochformat/Tablet):
  -- ScrolledWindow mit EXTERNAL fordert keine Breite an und schneidet notfalls ab.
  -- Die freie Fläche der Leiste dient als Titelleiste: ziehen = Fenster verschieben,
  -- Doppelklick = maximieren/wiederherstellen.
  local griff = Gtk.EventBox { visible_window = false }
  griff:add(leiste)
  function griff:on_button_press_event(ev)
    local b = ev.button
    if ev.type == "DOUBLE_BUTTON_PRESS" then
      if fenster.is_maximized then fenster:unmaximize() else fenster:maximize() end
      return true
    end
    if ev.type == "BUTTON_PRESS" and b.button == 1 then
      pcall(function() fenster:begin_move_drag(1, math.floor(b.x_root), math.floor(b.y_root), b.time) end)
      return true
    end
    return false
  end
  local rahmen = Gtk.ScrolledWindow { hscrollbar_policy = Gtk.PolicyType.EXTERNAL,
    vscrollbar_policy = Gtk.PolicyType.NEVER, propagate_natural_height = true, shadow_type = Gtk.ShadowType.NONE }
  klasse(rahmen, "lern-rahmen", true)
  rahmen:add(griff)
  local vp = rahmen:get_child()
  if vp and Gtk.Viewport:is_type_of(vp) then vp.shadow_type = Gtk.ShadowType.NONE end
  E.feldbreite = nil
  E.feldbreite_pruefen = function()
    -- schmales Fenster (Hochformat): Felder schmaler
    local schmal = fenster:get_allocated_width() < 1300
    if schmal == E.feldbreite then return end
    E.feldbreite = schmal
    ordner_feld.width_chars = schmal and 13 or 20
    name_feld.width_chars = schmal and 16 or 24
    unter_feld.width_chars = schmal and 10 or 14
  end
  pcall(E.feldbreite_pruefen)
  local zeile = Gtk.Overlay {}
  zeile:add(rahmen)
  zeile:add_overlay(fk)
  local sw = xournal
  while sw and not Gtk.ScrolledWindow:is_type_of(sw) do sw = sw:get_parent() end
  local adj = sw and sw:get_vadjustment()
  local function plus_pruefen()
    if not adj then unten:show(); pcall(E.art_markieren) return end
    local am_ende = adj.value + adj.page_size >= adj.upper - 40
    unten:set_visible(am_ende)
    if am_ende then pcall(E.art_markieren) end
  end
  if adj then
    adj.on_value_changed = plus_pruefen
    adj.on_changed = plus_pruefen
  end

  -- Ohne Fensterleiste (Titel/Minimieren/Maximieren); das Fenster läuft maximiert
  pcall(function() fenster:set_decorated(false) end)
  E.pfeile_weg = function()
    -- Ausklapp-Pfeile (GtkMenuButton neben dem Werkzeugknopf, z. B. Stift/Radierer) ausblenden;
    -- no_show_all, damit show_all beim Neuaufbau der Leiste sie nicht wieder zeigt
    local function lauf(w)
      if Gtk.MenuButton:is_type_of(w) then
        local box = w:get_parent()
        if box and Gtk.Box:is_type_of(box) and box:get_parent() and Gtk.ToolItem:is_type_of(box:get_parent()) then
          w:set_no_show_all(true)
          w:hide()
        end
        return
      end
      if Gtk.Container:is_type_of(w) and w ~= leiste then
        for _, c in ipairs(w:get_children()) do lauf(c) end
      end
    end
    lauf(hauptbox)
  end
  pcall(E.pfeile_weg)
  hauptbox:pack_start(zeile, false, false, 0)
  hauptbox:reorder_child(zeile, 0)                              -- ganz oben, über tbTop1/tbTop2 (Leiste im Hochformat)
  zeile:show_all()
  unter_zeigen()
  unten:show_all()
  info:hide()
  plus_pruefen()
  etikett_aktualisieren()
  if GLib then GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1000, etikett_aktualisieren) end
  return true
end

-- Alle Lernordner-Knöpfe mit Dialogen laufen als Hintergrund-Ablauf (s. im_hintergrund).
for _, name in ipairs({ "lernNeu", "lernPdf", "lernSuche", "lernVerwerfen" }) do
  _G[name] = im_hintergrund(name, _G[name])
end

------------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------------
function initUi()
  local knoepfe = {
    { T("Stift: Dicke und Farbe", "Pen: thickness and colour"), "lernStift", "LERN_STIFT", "lernordner-dicke" },
    { T("Neuer Zettel", "New note"), "lernNeu", "LERN_NEU", "lernordner-neu-symbolic" },
    { T("Öffnen", "Open"), "lernOeffnen", "LERN_OEFFNEN", "lernordner-oeffnen-symbolic" },
    { T("Notiz verwerfen", "Discard note"), "lernVerwerfen", "LERN_VERWERFEN", "lernordner-verwerfen-symbolic" },
    { T("Leiste folgt der Drehung", "Toolbar follows rotation"), "lernDrehen", "LERN_DREHEN", "lernordner-drehen-symbolic" },
    { T("Neue Seite", "New page"), "lernNeueSeite", "LERN_SEITE", "lernordner-neu-symbolic" },
    { T("PDF importieren", "Import PDF"), "lernPdf", "LERN_PDF", "lernordner-pdf-symbolic" },
    { T("Suche", "Search"), "lernSuche", "LERN_SUCHE", "lernordner-suche-symbolic" },
  }
  for _, k in ipairs(knoepfe) do
    app.registerUi({ menu = "Lernordner: " .. k[1], callback = k[2], toolbarId = k[3], iconName = k[4] })
  end
  os.execute("mkdir -p " .. q(HOME .. "/.cache"))
  -- Aufräumen im Hintergrund (unberührte Vorlagen > 1 Tag aus "00 Eingang")
  os.execute("python3 " .. q(HELFER) .. " aufraeumen >/dev/null 2>>" .. q(LOG) .. " &")
  -- Beobachter (zuletzt-Zettel, automatisch speichern). Erst per Timer – in initUi
  -- selbst gibt es noch keine Aktionsdatenbank.
  local GLib = glib()
  if GLib then GLib.timeout_add(GLib.PRIORITY_DEFAULT, 2000, beobachter) end
end
