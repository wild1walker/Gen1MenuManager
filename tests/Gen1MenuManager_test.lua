-- Standalone: luajit mods/Gen1MenuManager/tests/Gen1MenuManager_test.lua
-- Drives the real Loader, then calls ui.start_menu.items the way
-- src/ui/StartMenu.lua does and asserts on the list that comes back.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")

-- The fixture dataset, not Data:load(): this suite must run in a checkout
-- with no ROM imported.  Item and move names therefore come from the
-- catalog's own id fallback, which is exactly the path a player hits when a
-- mod adds an item the cache has never seen.
local run = T.sdk.loadMod("mods/Gen1MenuManager")
local Data = run.data
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

local loader = run.loader

-- The engine's own call site: a vanilla passthrough plus (game, items).
local function build(game, items)
  return Runtime.call("ui.start_menu.items",
    function(_, list) return list end, game, items)
end

local function labels(list)
  local out = {}
  for i, item in ipairs(list) do out[i] = item.label end
  return table.concat(out, ",")
end

-- The rows src/ui/StartMenu.lua actually produces for a mid-game save.
local function vanillaRows(name)
  return {
    { label = "POKéDEX" }, { label = "POKéMON" }, { label = "ITEM" },
    { label = name }, { label = "SAVE", keepOpen = true },
    { label = "OPTION" }, { label = "QUIT" },
  }
end

local function newGame(overrides)
  local game = {
    data = Data,
    save = {
      player = { name = "RED" }, party = {}, inventory = {}, flags = {},
      modData = {},
    },
  }
  for key, value in pairs(overrides or {}) do game.save[key] = value end
  loader.modSave = game.save.modData
  return game
end

-- ------- 1. no layout: vanilla order survives, plus the manager row

local game = newGame()
local out = build(game, vanillaRows("RED"))
T.eq(labels(out), "POKéDEX,POKéMON,ITEM,RED,SAVE,OPTION,QUIT,MENU MGR",
  "an unconfigured install appends its row and reorders nothing")

-- ------- 2. a saved order is applied, including to the player-name row

loader.modSave.Gen1MenuManager = { layout = { v = 1, hidden = {}, pins = {},
  order = { "L:ITEM", "@PLAYER", "L:POKéDEX" } } }
out = build(game, vanillaRows("RED"))
T.eq(labels(out), "ITEM,RED,POKéDEX,POKéMON,SAVE,OPTION,QUIT,MENU MGR",
  "named rows lead; everything else keeps engine order behind them")

-- the trainer-card row is keyed by the player's name, so a different save
-- with a different name still matches it
local other = newGame({ player = { name = "BLUE" } })
loader.modSave.Gen1MenuManager = { layout = { v = 1, hidden = {}, pins = {},
  order = { "@PLAYER" } } }
out = build(other, vanillaRows("BLUE"))
T.eq(out[1].label, "BLUE", "@PLAYER follows the name, not a literal")

-- ------- 3. hiding

game = newGame()
loader.modSave.Gen1MenuManager = { layout = { v = 1, order = {}, pins = {},
  hidden = { ["L:LINK"] = true, ["L:QUIT"] = true } } }
out = build(game, vanillaRows("RED"))
T.check(not labels(out):find("QUIT"), "a hidden row is dropped")
T.check(labels(out):find("MENU MGR"), "the manager row survives")

-- ------- 3b. hiding everything, with and without the SELECT shortcut

local function setOption(key, value)
  loader.modOptions.Gen1MenuManager = loader.modOptions.Gen1MenuManager or {}
  loader.modOptions.Gen1MenuManager[key] = value
end

local everything = { v = 1, order = {}, pins = {}, hidden = {} }
for _, row in ipairs(vanillaRows("RED")) do
  everything.hidden["L:" .. row.label] = true
end
-- the trainer-card row is keyed @PLAYER, not by the name it displays
everything.hidden["@PLAYER"] = true
everything.hidden["@MANAGER"] = true -- and try to hide the way back too
loader.modSave.Gen1MenuManager = { layout = everything }

-- shortcut ON: nothing is protected, because SELECT still reaches the editor
-- from an empty menu.  An empty result is not allowed either way, so the
-- layout degrades to showing everything rather than to a menu with no rows.
setOption("select_shortcut", true)
out = build(game, vanillaRows("RED"))
T.check(#out > 0, "a hide-everything layout never empties the menu")

-- shortcut OFF: the manager row is the only route left, so it locks
setOption("select_shortcut", false)
out = build(game, vanillaRows("RED"))
T.eq(labels(out), "MENU MGR", "with SELECT off the manager row cannot be hidden")
setOption("select_shortcut", true)

-- ------- 4. rows from another mod are arrangeable, not just vanilla ones

game = newGame()
loader.modSave.Gen1MenuManager = { layout = { v = 1, hidden = {}, pins = {},
  order = { "L:QUESTS" } } }
local withMod = vanillaRows("RED")
table.insert(withMod, 4, { label = "QUESTS" })
out = build(game, withMod)
T.eq(out[1].label, "QUESTS", "a row appended by another mod can be moved first")

-- ------- 5. pins appear only once the item is owned

game = newGame()
loader.modSave.Gen1MenuManager = { layout = { v = 1, order = {}, hidden = {},
  pins = { ["P:townmap"] = true, ["P:bicycle"] = true } } }
out = build(game, vanillaRows("RED"))
T.check(not labels(out):find("MAP"), "an unowned pin has no row")

game.save.inventory.TOWN_MAP = 1
out = build(game, vanillaRows("RED"))
T.check(labels(out):find("MAP"), "the pin appears once the item is in the bag")
T.check(not labels(out):find("TOWN MAP"),
  "and the row carries the pin's menuLabel, not the item name")
T.check(not labels(out):find("BICYCLE"), "the unowned pin still has none")

-- SHORT NAMES off hands the row back to the name the game itself uses
setOption("short_names", false)
out = build(game, vanillaRows("RED"))
T.check(labels(out):find("TOWN MAP"),
  "SHORT NAMES off puts the item name on the row")
setOption("short_names", true)
out = build(game, vanillaRows("RED"))
T.check(not labels(out):find("TOWN MAP"), "and back on again")

-- and a pin obeys the saved order like any other row
loader.modSave.Gen1MenuManager = { layout = { v = 1, hidden = {},
  pins = { ["P:townmap"] = true }, order = { "P:townmap" } } }
out = build(game, vanillaRows("RED"))
T.eq(out[1].label, "MAP", "a pin can be ordered ahead of the engine rows")

-- a move pin needs the badge as well as the move
game = newGame({ party = { { moves = { { id = "CUT" } } } } })
loader.modSave.Gen1MenuManager = { layout = { v = 1, order = {}, hidden = {},
  pins = { ["P:cut"] = true } } }
out = build(game, vanillaRows("RED"))
T.check(not labels(out):find("CUT"), "CUT without CASCADEBADGE is not offered")
game.save.inventory.CASCADEBADGE = 1
out = build(game, vanillaRows("RED"))
T.check(labels(out):find("CUT"), "CUT appears once the badge is in the bag")

-- ------- 6. a corrupt layout degrades instead of raising

game = newGame()
loader.modSave.Gen1MenuManager = { layout = "not a table" }
out = build(game, vanillaRows("RED"))
T.eq(#out, 8, "a garbage layout falls back to the built order")

loader.modSave.Gen1MenuManager = { layout = { v = 1, order = { "L:GONE", 42, "" },
  hidden = { [7] = true }, pins = { ["P:nosuch"] = true } } }
out = build(game, vanillaRows("RED"))
T.eq(#out, 8, "keys for rows and pins that do not exist are ignored")

-- ------- 7. the OPTION route in

local optionRows = Runtime.call("ui.options.rows",
  function(_, rows) return rows end, game, { { id = "text_speed" } })
T.eq(#optionRows, 2, "the options hook adds exactly one row")
T.eq(optionRows[2].label, "MENU MANAGER", "and it is the way back to the editor")
T.check(type(optionRows[2].activate) == "function",
  "options rows open screens through activate")

-- Anchored, not appended.  The engine groups the OPTION screen after this
-- hook runs and lays its own named rows out first, so an appended row lands
-- past the platform rows while every other mod row sits under MODS.
local anchored = Runtime.call("ui.options.rows",
  function(_, rows) return rows end, game,
  { { id = "text_speed" }, { id = "mods", label = "MODS" } })
T.eq(#anchored, 3, "still exactly one row added")
T.eq(anchored[2].label, "MENU MANAGER", "which sits before MODS")
T.eq(anchored[3].label, "MODS", "and MODS keeps its place after it")
T.check(anchored[2].top == true,
  "and it asks for the top, which Gen1ModMenu honours when installed")

-- ------- 8. the editor screen

-- A stand-in for game.input: one press per update, the shape Menu and
-- OptionsMenu drive (input:wasPressed(button)).
local function press(button)
  game.input = { wasPressed = function(_, name) return name == button end }
end

local popped = 0
game.stack = { pop = function() popped = popped + 1 end }

game.save.modData.Gen1MenuManager = nil
loader.modSave = game.save.modData
build(game, vanillaRows("RED")) -- populate the snapshot the editor reads

local Screens = require("src.ui.Screens")
local screen = Screens.build(game, "Gen1MenuManagerEditor", {})
T.check(type(screen.update) == "function" and type(screen.draw) == "function",
  "the editor is a stack state")
T.check(screen.isOpaque, "and an opaque one")
T.eq(screen.entries[1].label, "POKéDEX", "it lists the rows the menu just built")
T.check(#screen.entries > 8, "and every pin in the catalog after them")

-- A pin is listed in the editor under the item or move it comes from, even
-- when the row the player ends up with reads differently: the town map pin
-- is TOWN MAP here and MAP on the menu itself.
local function pinEntry(key)
  for _, entry in ipairs(screen.entries) do
    if entry.key == key then return entry end
  end
  return nil
end
T.eq(pinEntry("P:townmap").label, "TOWN MAP",
  "the editor lists a pin under the item it comes from")

-- grab the top row and walk it down one: A, DOWN, A
press("a"); screen:update()
T.check(screen.grabbed, "A grabs the row under the cursor")
press("down"); screen:update()
T.eq(screen.entries[1].label, "POKéMON", "DOWN while grabbed swaps the rows")
T.eq(screen.entries[2].label, "POKéDEX", "and carries the grabbed row with it")
press("a"); screen:update()
T.check(not screen.grabbed, "A drops it again")

out = build(game, vanillaRows("RED"))
T.eq(out[1].label, "POKéMON", "the move is live in the menu")
T.eq(out[2].label, "POKéDEX", "and persisted in order, not just on screen")

-- SELECT hides; the protected row refuses.  The cursor travelled with the
-- grabbed row, so it is sitting on POKéDEX now, not on POKéMON.
T.eq(screen.entries[screen.index].label, "POKéDEX", "the cursor rode along")
press("select"); screen:update()
out = build(game, vanillaRows("RED"))
T.check(not labels(out):find("POKéDEX"), "SELECT hides the row under the cursor")
T.check(labels(out):find("POKéMON"), "and leaves its neighbour alone")

local function cursorTo2(scr, key)
  for _ = 1, #scr.entries do
    if scr.entries[scr.index].key == key then return true end
    game.input = { wasPressed = function(_, n) return n == "down" end }
    scr:update()
  end
  return scr.entries[scr.index].key == key
end

local function cursorTo(key)
  for _ = 1, #screen.entries do
    if screen.entries[screen.index].key == key then return true end
    press("down"); screen:update()
  end
  return screen.entries[screen.index].key == key
end

T.check(cursorTo("@MANAGER"), "the manager row is in the list")
press("select"); screen:update()
T.check(not screen.entries[screen.index].on,
  "with SELECT OPENS on, the manager row hides like any other")
out = build(game, vanillaRows("RED"))
T.check(not labels(out):find("MENU MGR"), "and it really leaves the menu")

-- with the shortcut off it locks again, and the editor refuses the toggle
setOption("select_shortcut", false)
screen = Screens.build(game, "Gen1MenuManagerEditor", {})
T.check(cursorTo("@MANAGER"), "the row is still listed")
T.check(screen.entries[screen.index].locked, "and now reads LOCK")
local before = screen.entries[screen.index].on
press("select"); screen:update()
T.eq(screen.entries[screen.index].on, before, "SELECT will not switch it off")
setOption("select_shortcut", true)

press("b"); screen:update()
T.eq(popped, 1, "B leaves the editor")

-- ------- 9. the cache template round-trips
--
-- mod.save is per playthrough, so the same layout is encoded to mod.cache and
-- a save with no layout of its own seeds from it.  Bytes in, layout out.

local Layout = loadfile("mods/Gen1MenuManager/layout.lua")()
local sample = { v = 1, order = { "L:ITEM", "@PLAYER", "P:townmap" },
                 hidden = { ["L:QUIT"] = true }, pins = { ["P:townmap"] = true } }
local decoded = Layout.decode(Layout.encode(sample))
T.eq(table.concat(decoded.order, ","), "L:ITEM,@PLAYER,P:townmap",
  "the ordered block survives encoding in order")
T.check(decoded.hidden["L:QUIT"], "the hidden set survives")
T.check(decoded.pins["P:townmap"], "the pin set survives")
T.check(Layout.decode("garbage") == nil, "a foreign file is rejected, not parsed")
T.eq(#Layout.normalize(nil).order, 0, "and a missing layout is an empty one")

-- ------- 10. the SELECT shortcut
--
-- The engine leaves SELECT unbound in both menus: the START menu's watched-key
-- mask is PAD_DOWN | PAD_UP | PAD_START | PAD_B | PAD_A and src/ui/Menu.lua
-- reads up, down, a, b and start only.  So the shortcut takes nothing away.

local Menu = require("src.ui.Menu")
local pushed = {}
game.stack = {
  states = {},
  push = function(self, state)
    pushed[#pushed + 1] = state
    self.states[#self.states + 1] = state
    Runtime.emit("screen.pushed", { state = state })
  end,
  pop = function(self)
    popped = popped + 1
    table.remove(self.states)
  end,
  top = function(self) return self.states[#self.states] end,
}

game.save.modData.Gen1MenuManager = nil
loader.modSave = game.save.modData
local arranged = build(game, vanillaRows("RED"))

-- the engine builds a Menu over the arranged list and pushes it; screen.pushed
-- is how the mod finds that instance, matching on the list identity
local live = Menu.new(game, arranged, { tx = 9, ty = 0, tw = 11 })
live.screenId = "StartMenu"
game.stack:push(live)

popped = 0
pushed = {}
press("select")
live:update(0)
T.eq(popped, 1, "SELECT closes the START menu")
T.eq(#pushed, 1, "and opens exactly one screen")
T.eq(pushed[1].screenId, "Gen1MenuManagerEditor", "which is the editor")
T.eq(pushed[1].ctx.title, "START MENU", "editing the START menu layout")

-- with the option off, SELECT is inert and the row it sits on is untouched
setOption("select_shortcut", false)
local again = Menu.new(game, build(game, vanillaRows("RED")), {})
again.screenId = "StartMenu"
game.stack:push(again)
popped, pushed = 0, {}
press("select")
again:update(0)
T.eq(popped, 0, "SELECT OPENS off leaves the menu alone")
T.eq(#pushed, 0, "and opens nothing")
setOption("select_shortcut", true)

-- ------- 11. the PC menu
--
-- src/world/OverworldController.lua openPC builds its rows, runs them through
-- ui.pc.items, and appends LOG OFF AFTER the hook so a mod cannot orphan the
-- way out.  These are the rows a mid-game Pokémon Center PC produces.

local function pcRows(name)
  return {
    { label = "BILL'S PC", keepOpen = true },
    { label = name .. "'s PC", keepOpen = true },
    { label = "PROF.OAK's PC", keepOpen = true },
  }
end

local function buildPc(g, items)
  return Runtime.call("ui.pc.items", function(_, l) return l end, g, items)
end

game.save.modData.Gen1MenuManager = nil
loader.modSave = game.save.modData
local pc = buildPc(game, pcRows("RED"))
T.eq(labels(pc), "BILL'S PC,RED's PC,PROF.OAK's PC,MENU MGR",
  "the PC gets its own manager row")
T.check(pc[4].keepOpen, "which uses keepOpen like every other PC row")

-- the PC row for the player's own storage is labelled "<name>'s PC", so it
-- needs the same name-derived key the START menu's trainer card gets
loader.modSave.Gen1MenuManager = { pc_layout = { v = 1, hidden = {}, pins = {},
  order = { "@PLAYERPC" } } }
pc = buildPc(game, pcRows("RED"))
T.eq(pc[1].label, "RED's PC", "@PLAYERPC matches it whatever the name is")
pc = buildPc(other, pcRows("BLUE"))
T.eq(pc[1].label, "BLUE's PC", "on any save")

-- the two menus keep separate layouts
loader.modSave.Gen1MenuManager = {
  layout = { v = 1, hidden = {}, pins = {}, order = { "L:QUIT" } },
  pc_layout = { v = 1, hidden = {}, pins = {}, order = { "L:PROF.OAK's PC" } },
}
out = build(game, vanillaRows("RED"))
pc = buildPc(game, pcRows("RED"))
T.eq(out[1].label, "QUIT", "the START layout drives the START menu")
T.eq(pc[1].label, "PROF.OAK's PC", "and the PC layout drives the PC")

-- hiding in the PC, and the exit the engine appends afterwards
loader.modSave.Gen1MenuManager = { pc_layout = { v = 1, order = {}, pins = {},
  hidden = { ["L:PROF.OAK's PC"] = true } } }
pc = buildPc(game, pcRows("RED"))
T.check(not labels(pc):find("OAK"), "a PC row can be hidden")
pc[#pc + 1] = { label = "LOG OFF" } -- what openPC does after the hook
T.eq(pc[#pc].label, "LOG OFF", "LOG OFF is appended after the hook, never ours to lose")

-- Gold's PC rows carry a stable id, which outranks the label: it is neither
-- localized nor rewritten mid-playthrough (src/ui/gen2/ItemPcMenu.lua)
loader.modSave.Gen1MenuManager = { pc_layout = { v = 1, hidden = {}, pins = {},
  order = { "I:toss" } } }
pc = buildPc(game, {
  { id = "withdraw", label = "WITHDRAW ITEM" },
  { id = "deposit", label = "DEPOSIT ITEM" },
  { id = "toss", label = "TOSS ITEM" },
})
T.eq(pc[1].label, "TOSS ITEM", "an id-keyed row is ordered by its id")

-- ------- 12. a live PC menu is rebuilt when the editor closes
--
-- The PC session stays open under its sub-screens, and Menu sizes its box
-- from the row count at construction (openPC passes th = #items * 2 + 2), so
-- hiding a row has to resize the box too.

game.save.modData.Gen1MenuManager = nil
loader.modSave = game.save.modData
local pcArranged = buildPc(game, pcRows("RED"))
local pcMenu = Menu.new(game, pcArranged,
  { tx = 0, ty = 0, tw = 16, th = (#pcArranged + 1) * 2 + 2, noSound = true })
game.stack:push(pcMenu)
pcMenu.items[#pcMenu.items + 1] = { label = "LOG OFF" } -- the engine's append
local beforeCount = #pcMenu.items

popped, pushed = 0, {}
press("select")
pcMenu:update(0)
T.eq(popped, 0, "SELECT leaves the PC menu open underneath")
local editor = pushed[1]
T.eq(editor.ctx.title, "PC MENU", "and opens the editor on the PC layout")

T.check(cursorTo2(editor, "L:PROF.OAK's PC"), "the PC rows are listed")
game.input = { wasPressed = function(_, n) return n == "select" end }
editor:update()
game.input = { wasPressed = function(_, n) return n == "b" end }
editor:update()

T.eq(#pcMenu.items, beforeCount - 1, "the live PC menu lost the hidden row")
T.eq(pcMenu.items[#pcMenu.items].label, "LOG OFF", "and kept its exit")
T.eq(pcMenu.th, #pcMenu.items * 2 + 2, "the box was resized to match")
T.check(pcMenu.index <= #pcMenu.items, "the cursor is still in range")

-- ------- 12. the editor names a pin after the item, even while it is pinned
--
-- A pin that is ON reaches the editor through the menu snapshot, which
-- carries the label the MENU used -- the short one.  The editor has to reach
-- past that to the catalog, or the row would rename itself as the pin goes
-- on and off, and SHORT NAMES would rewrite the editor as well as the menu.

game = newGame({ inventory = { TOWN_MAP = 1 } })
loader.modSave.Gen1MenuManager = { layout = { v = 1, hidden = {}, order = {},
  pins = { ["P:townmap"] = true } } }
out = build(game, vanillaRows("RED"))
T.eq(out[#out].label, "MAP", "the pinned row reads MAP on the menu")

local function labelOf(scr, key)
  for _, entry in ipairs(scr.entries) do
    if entry.key == key then return entry.label end
  end
  return nil
end

local pinned = Screens.build(game, "Gen1MenuManagerEditor", {})
T.eq(labelOf(pinned, "P:townmap"), "TOWN MAP",
  "the editor lists a pin that is on under the item name")

setOption("short_names", false)
out = build(game, vanillaRows("RED"))
T.eq(out[#out].label, "TOWN MAP", "SHORT NAMES off puts the item name on the menu")
local vanilla = Screens.build(game, "Gen1MenuManagerEditor", {})
T.eq(labelOf(vanilla, "P:townmap"), "TOWN MAP",
  "and the editor is unmoved either way")
setOption("short_names", true)

-- ------- the editor walks between the menus it can arrange
--
-- One row on the OPTION screen opens this screen, and there are three menus
-- to arrange behind it.  LEFT and RIGHT are the only keys the editor was not
-- already using -- A grabs, SELECT toggles, UP and DOWN move, B and START
-- leave -- so they are what steps between them.

do
  local editor = Screens.build(game, "Gen1MenuManagerEditor", {})
  T.eq(editor.key, "start", "the editor opens on the menu it was asked for")
  T.check(type(editor.keys) == "table" and #editor.keys >= 2,
    "and knows the others it can reach")

  local titles = {}
  for i = 1, #editor.keys do
    titles[#titles + 1] = tostring(editor.ctx.title)
    press("right"); editor:update()
  end
  T.eq(editor.key, "start", "walking all the way round comes back")
  T.eq(table.concat(titles, ","), "START MENU,PC MENU,SELECT MENU",
    "and it visits every menu on the way, in a fixed order")

  press("left"); editor:update()
  T.eq(editor.ctx.title, "SELECT MENU", "LEFT walks the other way")
  press("right"); editor:update()
  T.eq(editor.ctx.title, "START MENU", "and RIGHT undoes it")

  -- a grab is modal: the row is in your hand, and carrying it onto another
  -- menu is not a move anyone means to make
  press("a"); editor:update()
  T.check(editor.grabbed, "A grabs a row")
  press("right"); editor:update()
  T.eq(editor.ctx.title, "START MENU",
    "and a held row pins the editor to the menu it came from")
  press("a"); editor:update()
  T.check(not editor.grabbed, "dropping it lets the editor move again")
  press("right"); editor:update()
  T.eq(editor.ctx.title, "PC MENU", "which it then does")
end

-- ------- the SELECT field menu is one of them
--
-- It is not an engine menu and has no engine hook: Gen1WildQOL builds it and
-- publishes a registry to hand the rows round.  This joins that registry, so
-- the context exists whether or not anything has opened the menu yet -- an
-- editor page that says PRESS SELECT FIRST is a better answer than a context
-- that is not there at all.

do
  local editor = Screens.build(game, "Gen1MenuManagerEditor",
                               { context = "select" })
  T.eq(editor.key, "select", "the editor opens on the SELECT menu when asked")
  T.eq(editor.ctx.title, "SELECT MENU", "and says which menu it is on")
  T.eq(editor.ctx.emptyHint, "PRESS SELECT FIRST",
    "and says how to fill it when nothing has been seen yet")
  T.check(editor.ctx.load ~= nil, "it has a layout of its own to load")

  -- CANCEL is protected there: B closes the menu too, but a way out you can
  -- SEE is not the same as one you have to know about
  local locked = editor.ctx.protected()
  T.check(locked["I:cancel"] == true,
    "and CANCEL cannot be hidden off the field menu")

  -- the SELECT layout is stored under its own key, so arranging one menu
  -- never disturbs another
  editor.ctx.save({})
  T.check(game.save.modData.Gen1MenuManager.select_layout ~= nil,
    "the SELECT arrangement is saved under a key of its own")
end

-- ------- nothing is drawn on the box's own border
--
-- The editor is one box, 20 by 18 tiles.  Row 16 is the hint line and row 17
-- is the frame's bottom edge, so a second line of hints lands ON the frame and
-- comes out as a smear over it.  Which is what a "< >:MENU" line did.  The
-- arrows live on the title now, where there is room and where the thing they
-- move is already named.

do
  local Font = require("src.render.Font")
  local editor = Screens.build(game, "Gen1MenuManagerEditor", {})

  local drawn = {}
  local realDraw = Font.draw
  Font.draw = function(text, x, y)
    drawn[#drawn + 1] = { text = tostring(text), x = x, y = y }
    return realDraw(text, x, y)
  end
  editor:draw()
  Font.draw = realDraw

  local onBorder = {}
  for _, d in ipairs(drawn) do
    -- 17 * 8: the bottom border row, and the row above it is the last
    -- interior one
    if d.y >= 17 * 8 then onBorder[#onBorder + 1] = d.text end
  end
  T.eq(table.concat(onBorder, ","), "",
    "no text is drawn on the frame's bottom edge")

  -- The title line says which menu, and how many there are.  Not "< TITLE >":
  -- `<` and `>` are not in the Game Boy font, so they drew as nothing and the
  -- only visible effect was the title sitting two columns further right.
  local onTitle = {}
  for _, d in ipairs(drawn) do
    if d.y == 8 then onTitle[#onTitle + 1] = d.text end
  end
  T.eq(onTitle[1], "START MENU", "the title is the title, undecorated")
  T.eq(onTitle[2], "1/3", "with the page count beside it")
  for _, text in ipairs(onTitle) do
    T.check(not text:find("[<>]"),
      "and nothing the font cannot draw: " .. text)
  end

  -- every line stays inside the box's interior, which is tiles 1 to 18
  local overflow = {}
  for _, d in ipairs(drawn) do
    local wide = d.x + #d.text * 8
    if d.x < 8 or wide > 19 * 8 then
      overflow[#overflow + 1] = ("%s@%d"):format(d.text, d.x)
    end
  end
  T.eq(table.concat(overflow, ","), "",
    "and no line reaches the left or right border")
end

-- ------- and the empty page fits inside its own box too
--
-- "NOTHING TO ARRANGE" is exactly 18 glyphs and the interior is tiles 1 to
-- 18, so starting it a column in put its last two characters on the border.

do
  local Font = require("src.render.Font")
  -- a PC menu nothing has opened yet: the snapshot is what the editor reads,
  -- and an earlier block in this suite has already filled this one in
  local probe = Screens.build(game, "Gen1MenuManagerEditor", { context = "pc" })
  local saved = probe.ctx.snapshot
  probe.ctx.snapshot = {}
  local empty = Screens.build(game, "Gen1MenuManagerEditor", { context = "pc" })
  T.eq(#empty.entries, 0, "a PC menu nothing has opened has nothing to arrange")

  local drawn = {}
  local realDraw = Font.draw
  Font.draw = function(text, x, y)
    drawn[#drawn + 1] = { text = tostring(text), x = x, y = y }
    return realDraw(text, x, y)
  end
  empty:draw()
  Font.draw = realDraw

  local said, overflow = {}, {}
  for _, d in ipairs(drawn) do
    said[#said + 1] = d.text
    if d.x < 8 or d.x + #d.text * 8 > 19 * 8 then
      overflow[#overflow + 1] = ("%s@%d"):format(d.text, d.x)
    end
  end
  T.check(table.concat(said, ","):find("NOTHING TO ARRANGE", 1, true) ~= nil,
    "and says so")
  T.eq(table.concat(overflow, ","), "",
    "inside the box, every glyph of it")
  probe.ctx.snapshot = saved
end

-- ------- a row the menu has not shown yet is still arrangeable
--
-- The field menu's rows appear only where they are usable: FLY outdoors,
-- FLASH in the dark, a repel while one is in the bag.  An editor that lists
-- only what it has SEEN can arrange almost none of it -- putting FLY in its
-- place would mean standing outdoors, with FLY in the party, holding the
-- editor open.  So the mod that builds the menu publishes a catalog of what
-- it can ever show, and the editor lists the rest of it.

do
  local ctx = nil
  -- reach the context the editor uses, through the editor itself
  local probe = Screens.build(game, "Gen1MenuManagerEditor", { context = "select" })
  ctx = probe.ctx

  local before = Screens.build(game, "Gen1MenuManagerEditor",
                               { context = "select" })
  local seenOnly = #before.entries

  ctx.catalog = function()
    return {
      { id = "fly", label = "FLY" },
      { id = "map", label = "MAP" },
      { id = "cancel", label = "CANCEL" },
    }
  end
  local after = Screens.build(game, "Gen1MenuManagerEditor",
                              { context = "select" })
  local labels = {}
  for _, entry in ipairs(after.entries) do
    labels[#labels + 1] = tostring(entry.label)
  end
  T.check(#after.entries > seenOnly,
    "the catalog puts rows in the editor the menu has never shown")
  T.eq(table.concat(labels, ","), "FLY,MAP,CANCEL",
    "every row the menu can show is listed, in the catalog's own order")

  -- and they can be switched off before they have ever appeared
  local flyEntry
  for _, entry in ipairs(after.entries) do
    if entry.key == "I:fly" then flyEntry = entry end
  end
  T.check(flyEntry ~= nil, "a catalog row is keyed by its id")
  T.check(flyEntry and flyEntry.on, "and starts shown")

  -- CANCEL is locked, catalog or not: it is the way out you can see
  local cancelEntry
  for _, entry in ipairs(after.entries) do
    if entry.key == "I:cancel" then cancelEntry = entry end
  end
  T.check(cancelEntry and cancelEntry.locked,
    "and CANCEL is locked even before the menu has shown it")

  -- A row the menu is not offering where the player is standing must not read
  -- ON.  Switching it on cannot put it on the menu -- what keeps it off is the
  -- game, not the layout -- and ON is a promise this screen cannot keep.  Four
  -- dashes, the same as a pin you do not own yet.
  T.check(flyEntry and flyEntry.absent,
    "a catalog row the menu is not offering is marked as absent")

  -- ...and what it DRAWS says so.  Read off the screen rather than rebuilt
  -- here: the marker column is the thing the player reads, and a test that
  -- formats its own copy of it proves nothing about the one on screen.
  local Font = require("src.render.Font")
  local cells = {}
  local realDraw = Font.draw
  Font.draw = function(text, x, y)
    cells[#cells + 1] = { text = tostring(text), x = x, y = y }
    return realDraw(text, x, y)
  end
  after:draw()
  Font.draw = realDraw

  local labelAt, markerAt = {}, {}
  for _, cell in ipairs(cells) do
    if cell.x == 2 * 8 then labelAt[cell.y] = cell.text end
    if cell.x == 15 * 8 then markerAt[cell.y] = cell.text end
  end
  local flyMarker
  for y, label in pairs(labelAt) do
    if label == "FLY" then flyMarker = markerAt[y] end
  end
  T.eq(flyMarker, "----",
    "and the row reads as dashes on screen rather than as ON")

  -- a catalog that raises costs the catalog, not the editor
  ctx.catalog = function() error("boom", 0) end
  local safe = Screens.build(game, "Gen1MenuManagerEditor",
                             { context = "select" })
  T.check(type(safe.entries) == "table",
    "and a catalog that raises does not take the editor down with it")
  ctx.catalog = nil
end

run.release()
require("src.ui.Screens").invalidate()
T.finish("Gen1MenuManager")
