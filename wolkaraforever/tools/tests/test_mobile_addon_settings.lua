-- The Interface mobile add-on's settings (addons/WolkaraRoue/Core.lua), run outside the game: a
-- 0.5 save moves to 0.6 once, then to 0.8's four wheels a side, each side's spells and notch
-- becoming its first wheel, the arc setting gone. The golden wheel's spells go into the left turning wheel, in its
-- free places and without duplicates, and the golden wheel is switched off but keeps them; the
-- left wheel turns and shows at least four spells; the chat goes back to its new place at the
-- bottom; the minimap gets its default size. A fresh install starts the same way, and a save
-- that has already moved is left as the player set it.
--
-- usage: luajit test_mobile_addon_settings.lua <path to Core.lua>

local path = assert(arg[1], "usage: luajit test_mobile_addon_settings.lua <Core.lua>")

local onEvent
CreateFrame = function()
    local frame = {}
    function frame:RegisterEvent() end
    function frame:SetScript(_, fn) onEvent = fn end
    return frame
end
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
InCombatLockdown = function() return false end

local ns = {}
assert(loadfile(path))("WolkaraRoue", ns)
local function Load(saved)
    WolkaraRoueDB = saved
    ns.db = nil
    onEvent(nil, "ADDON_LOADED", "WolkaraRoue")
    return ns.db
end
local function Entry(db, index, key, page)
    local button = db[key or "freeLeft"].pages[page or 1].buttons[index]
    return type(button) == "table" and button.entry or nil
end
-- Each side has its four wheels, the first shown, and no old layout left.
local function FourWheels(db)
    for _, key in ipairs({ "free", "freeLeft" }) do
        local side = db[key]
        for page = 1, ns.PAGES do assert(type(side.pages[page].buttons) == "table", key .. " wheel " .. page) end
        assert(side.buttons == nil and side.turnOffset == nil and side.turn == nil and side.page >= 1)
    end
    return true
end

-- A 0.5 save: the golden wheel on, with spells; the left side had one spell and one moved slot.
local db = Load({
    version = 2, layoutVersion = 3,
    wheels = { { enabled = true, slots = 8, scale = 100, radius = 110, open = "bouton", entries = {
        [1] = { kind = "spell", id = 100 }, [2] = { kind = "spell", id = 200 },
        [4] = { kind = "item", id = 300 }, [5] = { kind = "spell", id = 500 } } } },
    free = { count = 4, scale = 100, spread = 100, turn = true, turnOffset = 2, buttons = { [1] = { entry = { kind = "spell", id = 9 } } } },
    freeLeft = { count = 0, scale = 100, spread = 100, buttons = {
        [1] = { entry = { kind = "spell", id = 500 } }, [2] = { pos = { point = "CENTER", x = 1, y = 2 } } } },
    chat = { custom = true, fontSize = 18, pos = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 40 } },
})
assert(db.layoutVersion == 6 and FourWheels(db))
assert(db.wheels[1].enabled == false and db.wheels[1].entries[4].id == 300, "the golden wheel lost its spells or stayed on")
assert(db.freeLeft.count == 4, "the left wheel does not show four spells")
assert(Entry(db, 1).id == 500, "the left wheel's own spell was replaced")
assert(Entry(db, 2).id == 100, "a free place was not filled")
assert(Entry(db, 3).id == 200 and Entry(db, 4).kind == "item" and Entry(db, 4).id == 300)
assert(Entry(db, 5) == nil, "a spell already in the left wheel was added twice")
assert(db.chat.pos == nil and db.chat.fontSize == 18 and db.chat.tab == "talk", "the chat kept its old place")
assert(db.minimap.shown == true and db.minimap.scale == 60)
assert(db.free.pages[1].turnOffset == 2 and Entry(db, 1, "free").id == 9, "the right wheel changed")
assert(Entry(db, 1, "free", 2) == nil and Entry(db, 1, "freeLeft", 4) == nil, "a new wheel is not empty")

-- More spells than four: the left wheel shows them all.
db = Load({ version = 2, layoutVersion = 3, wheels = { { enabled = true, slots = 8, entries = {
    { kind = "spell", id = 1 }, { kind = "spell", id = 2 }, { kind = "spell", id = 3 },
    { kind = "spell", id = 4 }, { kind = "spell", id = 5 }, { kind = "spell", id = 6 } } } } })
assert(db.freeLeft.count == 6 and Entry(db, 6).id == 6)

-- A fresh install: the same start, nothing to move.
db = Load(nil)
assert(db.layoutVersion == 6 and db.freeLeft.count == 4 and FourWheels(db) and Entry(db, 1) == nil)
for i = 1, ns.MAX_WHEELS do assert(db.wheels[i].enabled == false, "a golden wheel is on by default") end

-- Already moved: the player's own choices stay.
db.wheels[1].enabled = true
db.freeLeft.count = 2
db.chat.pos = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 90 }
db = Load(db)
assert(db.wheels[1].enabled == true and db.freeLeft.count == 2 and db.chat.pos.y == 90, "the move ran twice")

-- A 0.7 save (layout 5): each side's spells and notch become its first wheel, once; the wheel
-- shown is kept within the four.
db = Load({ version = 2, layoutVersion = 5,
    free = { count = 6, scale = 100, spread = 100, turn = true, turnOffset = 3,
        buttons = { [2] = { entry = { kind = "spell", id = 75 } }, [5] = { entry = { kind = "item", id = 6948 } } } },
    freeLeft = { count = 4, scale = 100, spread = 100, turn = true, turnOffset = 1,
        buttons = { [1] = { entry = { kind = "spell", id = 13163 } } } } })
assert(db.layoutVersion == 6 and FourWheels(db))
assert(Entry(db, 2, "free").id == 75 and Entry(db, 5, "free").id == 6948 and db.free.pages[1].turnOffset == 3)
assert(Entry(db, 1).id == 13163 and db.freeLeft.pages[1].turnOffset == 1 and db.free.page == 1)
db.free.pages[3].buttons[1] = { entry = { kind = "spell", id = 1978 } }
db.free.page = 9
db = Load(db)
assert(Entry(db, 1, "free", 3).id == 1978 and Entry(db, 2, "free").id == 75 and db.free.page == 4, "the four wheels moved twice")

-- An error caught by the guard stays in the save, once per kind with its count, eight at most:
-- the game logs none of them, and the chat cannot be read from the Mac.
local function Fail(label, message) return ns.Guard(label, function() error(message, 0) end) end
assert(Fail("expérience", "boom") == false)
Fail("expérience", "boom")
assert(#db.errors == 1 and db.errors[1].count == 2 and db.errors[1].text:find("^expérience : boom"), "the error is not kept")
for i = 1, 10 do Fail("autre", "problème " .. i) end
assert(#db.errors == 8 and db.errors[1].text:find("problème 10"), "the newest errors are not the ones kept")
db = Load(db)
assert(#db.errors == 8, "the kept errors went at load")

print("mobile add-on settings: 0.5 golden wheel moved into the left wheel once, no duplicate or overwrite, chat and minimap defaults, a 0.7 save moved once into four wheels a side, caught errors kept in the save: PASS")
