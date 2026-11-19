-- Etikett-Leiste: Ablauf Ordner → Name → Tags, Nummern, Rückgängig, neue Seite.
-- Attrappe der app-API; Dokument = eine .xopp im Wegwerf-Basisordner.
local BASIS = os.getenv("LERNORDNER_BASIS")
geoeffnet = BASIS .. "/00 Eingang/2026-11-07 22-18.xopp"
seiten = 1
-- Texte der (einzigen) Seite; alte sichtbare Platzhalter-Tag-Zeile wie in alten Notizen
texte = { { text = "#", font = { size = 10 }, color = 0x808080, x = 80, y = 56, ref = "t1" },
          { text = "Notiz zu #Asthma", font = { size = 12 }, color = 0, x = 80, y = 200, ref = "t2" } }
aktionen = {}
local function speichern()   -- wie Xournal: neue Datei schreiben (neue Inode)
  local f = io.open(geoeffnet, "rb"); local d = f:read("a"); f:close()
  -- neu schreiben (neue Datei, neue Zeit) wie Xournal; gzip-Dateien unverändert lassen,
  -- ein angehängtes Zeichen würde sie unlesbar machen
  if d:sub(1, 2) ~= "\x1f\x8b" then d = d .. "\n" end
  os.remove(geoeffnet); f = io.open(geoeffnet, "wb"); f:write(d); f:close()
end
auswahl = {}
local nr = 0
app = {
  C = { Tool_text = 99, Tool_pen = 1 },
  getDocumentStructure = function()
    local p = {}
    for i = 1, seiten do p[i] = { isAnnotated = true, pdfBackgroundPageNo = 0, pageTypeFormat = seitenart or "lined" } end
    return { xoppFilename = geoeffnet, currentPage = seiten, pages = p, pdfBackgroundFilename = "" }
  end,
  openFile = function(p) geoeffnet = p; print("  openFile", (p:gsub("^.*/basis/", ""))) end,
  registerUi = function() end, getActionState = function() return 1 end,
  activateAction = function(a)
    aktionen[#aktionen + 1] = a
    if a == "save" then speichern()
    elseif a == "new-page-at-end" then seiten = seiten + 1; texte = {}
    elseif a == "delete" then
      for _, r in ipairs(auswahl) do
        for i = #texte, 1, -1 do if texte[i].ref == r then table.remove(texte, i) end end
      end
    end
  end,
  addToSelection = function(r) auswahl = r end, clearSelection = function() auswahl = {} end,
  addTexts = function(a) for _, t in ipairs(a.texts) do nr = nr + 1; t.ref = "n" .. nr; texte[#texte + 1] = t end end,
  getTexts = function() return texte end, getStrokes = function() return {} end, getImages = function() return {} end,
  refreshPage = function() end, changeCurrentPageBackground = function(a) seitenart = a end, scrollToPage = function() end, setCurrentPage = function() end,
}
local src = io.open(arg[1]):read("a") .. "\n_G.__einh = etikett_einhaengen; _G.__gtk = gtk; _G.__E = function() return E end; _G.__busy = function() return beschaeftigt end"
assert(load(src, "@" .. arg[1]))()
local Gtk = __gtk().Gtk; local GLib = require("lgi").GLib

-- Fenster wie main.glade: Window > Overlay(mainOverlay) > Box(mainBox: tbTop1, tbTop2, …) > ScrolledWindow > GtkXournal
local fenster = Gtk.Window {}; local ov = Gtk.Overlay {}; fenster:add(ov)
local mainbox = Gtk.Box { orientation = Gtk.Orientation.VERTICAL }; ov:add(mainbox)
mainbox:add(Gtk.Toolbar {}); mainbox:add(Gtk.Toolbar {})
local sw = Gtk.ScrolledWindow {}; mainbox:add(sw)
local xo = Gtk.DrawingArea { can_focus = true }; xo:set_name("GtkXournal"); sw:add(xo)
assert(__einh(fenster) == true)
initUi()                          -- Beobachter (Verlauf, Aufträge der GNOME-Suche)
local E = __E()
local function warte(ms)
  if _G.__aktivieren then __aktivieren() end   -- Testfenster bleibt „aktiv“ (siehe unten)
  local l = GLib.MainLoop(); GLib.timeout_add(0, ms, function() l:quit() return false end); l:run()
end
-- wartet, bis kein Ablauf mehr läuft (Speichern/Verschieben dauern je nach Last), dann noch
-- einen Takt der Leiste (1 s); höchstens 20 s
local function warte_ruhe()
  warte(300)
  local n = 0
  while __busy() and n < 200 do warte(100); n = n + 1 end
  warte(1300)
end
local function zeige(titel)
  local chips = {}
  for _, t in ipairs(E.tags) do chips[#chips + 1] = t end
  for _, t in ipairs(E.text_tags) do chips[#chips + 1] = "(" .. t .. ")" end
  print(titel, "[" .. E.ordner_nr:get_text() .. "] " .. E.ordner_feld:get_text() .. " / [" .. E.name_nr:get_text() ..
        "] " .. E.name_feld:get_text() .. " · " .. table.concat(chips, " "), E.modus and "MODUS" or "")
end
local function vorschlaege()
  local t = {}
  if E.pop and E.pop:get_visible() then
    for _, b in ipairs(E.pop_box:get_children()) do t[#t + 1] = b:get_child():get_text() end
  end
  return table.concat(t, " | ")
end
local function waehle(text)                 -- Vorschlag antippen
  for _, b in ipairs(E.pop_box:get_children()) do
    if b:get_child():get_text():find(text, 1, true) then b:clicked() return end
  end
  error("Vorschlag fehlt: " .. text)
end
fenster:show_all()
-- Das Testfenster erscheint auf dem echten Bildschirm und wird dort nicht unbedingt aktiv;
-- GTK schickt focus-in/-out aber nur an aktive Fenster → Aktivierung einmal selbst melden.
function __aktivieren()
  if fenster.is_active then return end
  local Gdk1 = require("lgi").Gdk
  local ev = Gdk1.Event(Gdk1.EventType.FOCUS_CHANGE)
  ev.focus_change["in"] = 1
  ev.focus_change.window = fenster:get_window()
  fenster:send_focus_change(ev)
end
__aktivieren()
print("Testfenster aktiv:", fenster.is_active)
xo:grab_focus()
warte(1300)
zeige("Start:")
print("  alte Tag-Zeile unsichtbar? ", #texte, texte[#texte] and texte[#texte].y)

-- ＋ Neu (aktuelles Blatt hat Inhalt → neues Blatt im Eingang), dann Ablauf
lernNeu(); warte_ruhe()
zeige("nach ＋:")
print("  Fokus im Namefeld (zuerst):", E.name_feld.is_focus, " Vorschläge:", vorschlaege():sub(1, 110))
-- Kapitel über alle Ordner suchen: Auswahl wählt den Ordner mit
E.name_feld:set_text("gich"); print("  'gich' global:", vorschlaege())
E.name_feld:set_text("Diabetes"); print("  'Diabetes' (schon angelegt) global:", "[" .. vorschlaege() .. "]")
-- Rücktaste im leeren Namensfeld → zurück ins Ordnerfeld
local Gdk0 = require("lgi").Gdk
local function rueck(feld) local ev = Gdk0.Event(Gdk0.EventType.KEY_PRESS); ev.key.keyval = 0xff08; ev.key.window = feld:get_window(); return feld:event(ev) end
E.name_feld:set_text(""); rueck(E.name_feld); warte(200)
print("  Rücktaste im leeren Namen → Fokus Ordner:", E.ordner_feld.is_focus, " Cursor am Ende:", E.ordner_feld:get_position() == E.ordner_feld:get_text_length())
E.name_feld:grab_focus(); warte(200); E.name_feld:set_text("gich"); waehle("Gicht"); warte(200)
print("  'Gicht' gewählt: Ordner", E.ordner_nr:get_text(), E.ordner_feld:get_text(), " Name", E.name_nr:get_text(), E.name_feld:get_text(), " Fokus Tags:", E.tag_feld.is_focus)
warte_ruhe()
print("  →", (geoeffnet:gsub("^.*/basis/", "")))
lernAblageRueckgaengig(); warte_ruhe(); warte(1200)
print("  zurück:", (geoeffnet:gsub("^.*/basis/", "")))
-- alter Weg: erst Ordner, dann Name
E.ordner_feld:grab_focus(); warte(150)
E.ordner_feld:set_text("chron"); print("  'chron':", vorschlaege(), " Nr:", E.ordner_nr:get_text())
E.ordner_feld:set_text("Kardiologie"); print("  'Kardiologie':", vorschlaege(), " Nr:", E.ordner_nr:get_text())
E.ordner_feld:set_text("chron"); E.ordner_feld:activate(); warte(200)
print("  Fokus im Namefeld:", E.name_feld.is_focus, " Vorschläge:", vorschlaege():sub(1, 90))
E.name_feld:set_text("Gic"); print("  'Gic':", vorschlaege(), " Nr:", E.name_nr:get_text())
E.name_feld:set_text("Long Covid"); print("  'Long Covid':", vorschlaege(), " Nr:", E.name_nr:get_text())
E.name_feld:activate(); warte_ruhe()
print("  nach Name-Enter:", (geoeffnet:gsub("^.*/basis/", "")), " Fokus Tags:", E.tag_feld.is_focus, " Info:", E.info:get_visible() and E.info_text:get_text())
E.tag_feld:set_text("Lunge "); E.tag_feld:set_text("Lunge COPD,"); warte(100)
zeige("Tags getippt:")
E.tag_feld:activate(); warte(300)                  -- Enter im leeren Feld = fertig
zeige("nach Fertig:")
print("  Tag-Text:", texte[#texte].text, texte[#texte].y, " gespeichert:", aktionen[#aktionen])

-- Rückgängig
lernAblageRueckgaengig(); warte_ruhe()
print("Rückgängig →", (geoeffnet:gsub("^.*/basis/", "")))
warte(1200); zeige("danach:")

-- Neuer Ordner über die Leiste
E.ordner_feld:grab_focus(); warte(150)
E.ordner_feld:set_text("Kardiologie"); waehle("Kardiologie"); warte(200)
print("  neuer Ordner gewählt, Nr:", E.ordner_nr:get_text(), " Name-Vorschläge:", vorschlaege())
E.name_feld:set_text("EKG Grundlagen"); print("  Nr:", E.name_nr:get_text())
xo:grab_focus(); warte_ruhe()                    -- ins Dokument tippen = fertig
print("  →", (geoeffnet:gsub("^.*/basis/", "")))
warte(1200); zeige("danach:")

-- Pfeiltasten: ↓ wählt, → übernimmt und springt weiter
local Gdk = require("lgi").Gdk
local function taste(feld, k)
  local ev = Gdk.Event(Gdk.EventType.KEY_PRESS); ev.key.keyval = k; ev.key.window = feld:get_window()
  return feld:event(ev)
end
E.ordner_feld:grab_focus(); warte(150)
E.ordner_feld:set_text("e"); print("Pfeile: Vorschläge 'e':", vorschlaege())
taste(E.ordner_feld, 0xff54); taste(E.ordner_feld, 0xff54)
E.ordner_feld:set_position(-1); taste(E.ordner_feld, 0xff53); warte(200)
print("  nach ↓↓→: Ordner", E.ordner_nr:get_text(), E.ordner_feld:get_text(), " Fokus Name:", E.name_feld.is_focus, " Fokus Tags:", E.tag_feld.is_focus)
xo:grab_focus(); warte_ruhe()
print("  →", (geoeffnet:gsub("^.*/basis/", "")))
warte(1200)

-- Neue Seite: ohne Tags erst Erinnerung
texte = { { text = "Inhalt ohne Tag", font = { size = 12 }, color = 0, x = 80, y = 200, ref = "y" } }; warte(1200)
lernNeueSeite(); print("Seite+ ohne Tags: Seiten", seiten, " Hinweis:", E.info_text:get_text(), " Fokus Tags:", E.tag_feld.is_focus)
lernNeueSeite(); print("Seite+ nochmal:   Seiten", seiten)
texte = { { text = "#herz", font = { size = 10 }, color = 0x808080, x = 0, y = -40, ref = "x" } }; warte(1200)
lernNeueSeite(); print("Seite+ mit Tags:  Seiten", seiten)

-- Seitenart unten
E.art_knoepfe["graph"]:clicked(); warte(1200)
print("Seitenart:", seitenart, " markiert kariert:", E.art_knoepfe["graph"]:get_style_context():has_class("lern-gewaehlt"))
-- Fensterknöpfe vorhanden?
print("Fensterleiste aus:", not fenster.decorated)
-- Auftrag aus der GNOME-Suche
local st = os.getenv("XDG_STATE_HOME") .. "/lernordner"
os.execute("mkdir -p '" .. st .. "'")
local ziel = BASIS .. "/03 Chronische Erkrankungen/063 Diabetes mellitus.xopp"
local f = io.open(st .. "/oeffnen", "w"); f:write(ziel .. "\n"); f:close()
-- warten, bis der Beobachter (alle 2 s) den Auftrag abgeholt und die Notiz geöffnet hat
for _ = 1, 100 do if geoeffnet == ziel then break end warte(100) end
warte_ruhe()
print("Auftrag geöffnet:", (geoeffnet:gsub("^.*/basis/", "")), " Auftrag weg:", io.open(st .. "/oeffnen") == nil)
local v = io.open(st .. "/verlauf"); print("Verlauf:", v and (v:read("a"):gsub(BASIS .. "/", ""):gsub("\n", " | ")) or "-")

-- Unterordner mit "/": dritte Ebene (erst warten, bis die Leiste die geöffnete Notiz zeigt)
warte_ruhe()
E.name_feld:grab_focus(); warte(150)
E.name_feld:set_text("Diabetes/Insulin"); warte(100)
print("Unterordner: sichtbar", E.unter_feld:get_visible(), "[" .. E.unter_nr:get_text() .. "] " .. E.unter_feld:get_text(),
      " Name [" .. E.name_nr:get_text() .. "] " .. E.name_feld:get_text())
E.name_feld:set_text("Insulin/x"); warte(100)
print("  vierte Ebene abgelehnt:", E.info_text:get_text(), " Name:", E.name_feld:get_text())
E.name_feld:set_text("Insulin")
xo:grab_focus(); warte_ruhe()
print("  →", (geoeffnet:gsub("^.*/basis/", "")))
warte(1200); zeige("danach:")
print("  Unterordner-Feld nach dem Öffnen:", E.unter_feld:get_visible(), E.unter_feld:get_text())
-- Rücktaste-Kette: leerer Name → Unterordner → (leer) → Unterordner-Ebene weg, Ordner
local function rt(feld) local ev = Gdk.Event(Gdk.EventType.KEY_PRESS); ev.key.keyval = 0xff08; ev.key.window = feld:get_window(); return feld:event(ev) end
E.name_feld:grab_focus(); warte(150); E.name_feld:set_text(""); rt(E.name_feld); warte(150)
print("  Rücktaste leerer Name → Unterordner-Feld:", E.unter_feld.is_focus)
E.unter_feld:set_text(""); rt(E.unter_feld); warte(150)
print("  Rücktaste leerer Unterordner → Ebene weg:", not E.unter_feld:get_visible(), " Fokus Ordner:", E.ordner_feld.is_focus)
local ev0 = Gdk.Event(Gdk.EventType.KEY_PRESS); ev0.key.keyval = 0xff1b; ev0.key.window = E.ordner_feld:get_window(); E.ordner_feld:event(ev0); warte(300)

-- Escape setzt zurück
warte(1200)
E.name_feld:grab_focus(); E.name_feld:set_text("Quatsch")
local ev = require("lgi").Gdk.Event(require("lgi").Gdk.EventType.KEY_PRESS); ev.key.keyval = 0xff1b; ev.key.window = E.name_feld:get_window()
E.name_feld:event(ev); warte(200)
zeige("nach Escape:")

-- Notiz verwerfen: Dialog (Ersatz-zenity antwortet „ja“) → frisches Blatt, alte Notiz im Papierkorb
local alt = geoeffnet
local function da(p) local f = io.open(p, "rb"); if f then f:close() return true end return false end
lernVerwerfen(); warte_ruhe()
print("verwerfen: neues Blatt offen:", geoeffnet ~= alt and geoeffnet:match("/00 Eingang/[^/]+$") ~= nil,
      " alte Datei weg:", not da(alt))
local korb = io.popen("ls '" .. BASIS .. "/.papierkorb' 2>/dev/null"):read("a")
print("verwerfen: im Papierkorb:", korb:find((alt:match("([^/]+)$") or "?"), 1, true) ~= nil)
