-- Attrappe der app-API; Dokument aktuell = leeres Eingang-Blatt ohne Pfad
geoeffnet = nil
app = {
  C = { Tool_text = 99 },
  getDocumentStructure = function() return { xoppFilename = geoeffnet or "", pages = {} } end,
  openFile = function(p) geoeffnet = p; print("openFile", p) end,
  registerUi = function() end, getActionState = function() return 0 end,
  activateAction = function() end, scrollToPage = function() end,
}
local src = io.open(arg[1]):read("a") .. "\n_G.__baue = baue_oeffnen; _G.__gtk = gtk"
assert(load(src, "@" .. arg[1]))()
local Gtk = __gtk().Gtk; local GLib = require("lgi").GLib
local anker = Gtk.Button {}
local fenster = Gtk.Window {}; fenster:add(anker)
-- Unterordner mit einem Zettel für die dritte Ebene
local B = os.getenv("LERNORDNER_BASIS")
os.execute("python3 plugin/Lernordner/lernordner.py ordner-neu Diabetes --in '03 Chronische Erkrankungen' >/dev/null")
os.execute("cp plugin/Lernordner/template.xopp '" .. B .. "/03 Chronische Erkrankungen/01 Diabetes/001 Insulin.xopp'")
local pop = __baue(Gtk, anker)
local function alle(w, f)
  f(w)
  if Gtk.Container:is_type_of(w) then for _, c in ipairs(w:get_children()) do alle(c, f) end end
end
local function knopf_mit(wurzel, muster)
  local gef
  alle(wurzel, function(w)
    if not gef and Gtk.Button:is_type_of(w) then
      alle(w, function(l) if Gtk.Label:is_type_of(l) and l:get_label():find(muster, 1, true) then gef = w end end)
    end
  end)
  return gef
end
knopf_mit(pop, "03 Chronische"):clicked()
local stapel = pop:get_child()
local inhalt = stapel:get_child_by_name("inhalt")
local feld; alle(inhalt, function(w) if Gtk.Entry:is_type_of(w) then feld = w end end)
assert(feld, "kein Eingabefeld")
assert(knopf_mit(inhalt, "＋ 061 Bluthochdruck"), "graues ＋ fehlt")
assert(knopf_mit(inhalt, "063 Diabetes mellitus  ✓"), "✓ fehlt")
local u = knopf_mit(inhalt, "▸ 01 Diabetes")
assert(u, "Unterordner-Zeile fehlt")
u:clicked()
local inhalt2 = stapel:get_child_by_name("inhalt2")
print("Unterordner geöffnet:", stapel:get_visible_child_name(), " Zurück:", knopf_mit(inhalt2, "‹  01 Diabetes") ~= nil,
      " Zettel:", knopf_mit(inhalt2, "001 Insulin") ~= nil, " Neues Kapitel:", knopf_mit(inhalt2, "Neues Kapitel") ~= nil)
knopf_mit(inhalt2, "‹  01 Diabetes"):clicked()
print("zurück in:", stapel:get_visible_child_name())
knopf_mit(inhalt, "Neues Kapitel"):clicked()
print("sichtbar:", feld:get_parent():get_visible_child_name())
feld:set_text("hyperlip")
local sichtbar = 0
alle(inhalt, function(w) if Gtk.Button:is_type_of(w) and w:get_visible() and w ~= knopf_mit(inhalt, "Neues Kapitel") then sichtbar = sichtbar + 1 end end)
print("sichtbare Knöpfe nach Filter (inkl. Zurück + Zettel):", sichtbar)
feld:set_text("Ärger mit Übelkeit")
feld:activate()
local loop = GLib.MainLoop()
GLib.timeout_add(GLib.PRIORITY_DEFAULT, 3000, function() loop:quit() return false end)
loop:run()
print("ENDE geoeffnet =", geoeffnet)
