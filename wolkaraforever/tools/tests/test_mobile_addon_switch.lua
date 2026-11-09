-- The switch between the two Interface mobile add-ons installed side by side (addons/WolkaraRoue
-- and addons/WolkaraRoueDuo, the same Switch.lua in both), run outside the game with the few WoW
-- functions it calls stubbed. Asserted: it turns the other one on and itself off for this
-- character, then reloads; never in combat; never when the other is not installed; and it works
-- with the C_AddOns namespace as well as with the old global functions.
--
-- usage: luajit test_mobile_addon_switch.lua <WolkaraRoue/Switch.lua> <WolkaraRoueDuo/Switch.lua>

local mine = assert(arg[1], "usage: luajit test_mobile_addon_switch.lua <Switch.lua> <Duo Switch.lua>")
local duo = assert(arg[2], "usage: luajit test_mobile_addon_switch.lua <Switch.lua> <Duo Switch.lua>")

local combat, reloads, calls, installed, printed, enabled, saves, refuse

local function reset()
    combat, reloads, calls, printed, saves, refuse = false, 0, {}, {}, 0, false
    installed = { WolkaraRoue = true, WolkaraRoueDuo = true }
    enabled = { WolkaraRoue = 2, WolkaraRoueDuo = 0 }
end

local function api()
    return {
        GetAddOnInfo = function(name)
            if installed[name] then return name, name, "", true, nil end
            return name, nil, nil, false, "MISSING"
        end,
        EnableAddOn = function(name, character)
            calls[#calls + 1] = "enable " .. name .. " " .. tostring(character)
            if not refuse then enabled[name] = 2 end
        end,
        DisableAddOn = function(name, character)
            calls[#calls + 1] = "disable " .. name .. " " .. tostring(character)
            if not refuse then enabled[name] = 0 end
        end,
        -- The game forgets an add-on change it was not told to save (2026-11-09).
        SaveAddOns = function() saves = saves + 1 end,
    }
end

InCombatLockdown = function() return combat end
local created = {}
CreateFrame = function(kind, name, parent, template)
    local frame = { kind = kind, parent = parent, template = template, attributes = {}, scripts = {} }
    function frame:SetAttribute(key, value) self.attributes[key] = value end
    function frame:SetScript(script, fn) self.scripts[script] = fn end
    function frame:SetAllPoints(other) self.over = other end
    function frame:SetFrameLevel(level) self.level = level end
    function frame:RegisterForClicks(...) self.clicks = { ... } end
    created[#created + 1] = frame
    return frame
end
ReloadUI = function() reloads = reloads + 1 end
UnitName = function() return "Joueur" end
SlashCmdList = {}

local function load(path, addon, namespaced)
    local ns = { db = {}, Print = function(message) printed[#printed + 1] = message end }
    if namespaced then
        C_AddOns = api()
        -- C_AddOns asks (name, character).
        C_AddOns.GetAddOnEnableState = function(name, character)
            assert(installed[name] and character == "Joueur", "C_AddOns order is (name, character)")
            return enabled[name]
        end
        GetAddOnInfo, EnableAddOn, DisableAddOn, SaveAddOns, GetAddOnEnableState = nil, nil, nil, nil, nil
    else
        C_AddOns = nil
        local old = api()
        GetAddOnInfo, EnableAddOn, DisableAddOn, SaveAddOns = old.GetAddOnInfo, old.EnableAddOn, old.DisableAddOn, old.SaveAddOns
        -- The old global asks (character, name).
        GetAddOnEnableState = function(character, name)
            assert(installed[name] and character == "Joueur", "the old global order is (character, name)")
            return enabled[name]
        end
    end
    assert(loadfile(path))(addon, ns)
    return ns
end

for _, namespaced in ipairs({ true, false }) do
    -- From ours to the Duo one.
    reset()
    local ns = load(mine, "WolkaraRoue", namespaced)
    assert(ns.OTHER_INTERFACE == "WolkaraRoueDuo")
    assert(ns.OTHER_INTERFACE_LABEL == "Interface Duo")
    assert(ns.SwitchInterface() == true)
    assert(calls[1] == "enable WolkaraRoueDuo Joueur" and calls[2] == "enable WolkaraRoueDuo nil", calls[2])
    assert(calls[3] == "disable WolkaraRoue Joueur" and calls[4] == "disable WolkaraRoue nil", calls[3])
    assert(saves == 1, "the add-on change was not saved before the reload")
    assert(reloads == 1)
    assert(ns.db.switchLog.to == "WolkaraRoueDuo" and ns.db.switchLog.saved == true and ns.db.switchLog.state == 2)

    -- And back, through the slash command.
    reset()
    ns = load(duo, "WolkaraRoueDuo", namespaced)
    assert(ns.OTHER_INTERFACE == "WolkaraRoue")
    assert(ns.OTHER_INTERFACE_LABEL == "Interface pookee")
    assert(SLASH_WOLKARAUI1 == "/wolkaraui")
    enabled = { WolkaraRoue = 0, WolkaraRoueDuo = 2 }
    SlashCmdList.WOLKARAUI("")
    assert(calls[1] == "enable WolkaraRoue Joueur", calls[1])
    assert(calls[3] == "disable WolkaraRoueDuo Joueur", calls[3])
    assert(saves == 1 and reloads == 1)

    -- The game keeps the other one off: no reload for nothing, the player is told.
    reset()
    refuse = true
    ns = load(mine, "WolkaraRoue", namespaced)
    assert(ns.SwitchInterface() == false and reloads == 0 and #printed == 1)
    assert(ns.db.switchLog.state == 0)

    -- Never in combat: nothing changes, the player is told.
    reset()
    ns = load(mine, "WolkaraRoue", namespaced)
    combat = true
    assert(ns.SwitchInterface() == false)
    assert(#calls == 0 and reloads == 0 and #printed == 1)

    -- The other one missing: nothing is disabled, so the player is never left with none.
    reset()
    installed.WolkaraRoueDuo = nil
    ns = load(mine, "WolkaraRoue", namespaced)
    assert(ns.SwitchInterface() == false)
    assert(#calls == 0 and reloads == 0 and #printed == 1)
end

-- The menu tile and the Duo window's button: a secure button that runs the game's own /reload
-- (an add-on's ReloadUI did nothing on the iPhone, 2026-11-09), prepared just before the touch.
reset()
local ns = load(mine, "WolkaraRoue", true)
assert(ns.RELOAD_MACRO == "/stopmacro [combat]\n/reload")
local look = { GetFrameLevel = function() return 3 end }
local over = ns.SecureSwitchOver(look)
assert(over.template == "SecureActionButtonTemplate" and over.parent == look and over.over == look and over.level == 8)
assert(over.attributes.type == "macro" and over.attributes.macrotext == ns.RELOAD_MACRO)
assert(#over.clicks == 2, "the secure button must take the press and the release")
-- The press prepares (other on, this one off) and lets the macro reload; the release does it
-- again quietly, as the game passes the same touch twice.
over.scripts.PreClick(over, "LeftButton", true)
assert(over.attributes.type == "macro" and calls[1] == "enable WolkaraRoueDuo Joueur" and calls[3] == "disable WolkaraRoue Joueur")
assert(saves == 1, "the button did not save the add-on change before its reload")
over.scripts.PreClick(over, "LeftButton", false)
assert(over.attributes.type == "macro" and #printed == 0 and reloads == 0, "the button reloaded by itself")
-- Nothing to switch to: no reload, said once.
reset()
installed.WolkaraRoueDuo = nil
over.scripts.PreClick(over, "LeftButton", true)
over.scripts.PreClick(over, "LeftButton", false)
assert(over.attributes.type == nil and #calls == 0 and #printed == 1)
-- In combat its attributes are left alone (the macro's /stopmacro [combat] keeps it from
-- reloading); out of combat again it switches.
reset()
combat = true
over.scripts.PreClick(over, "LeftButton", true)
assert(over.attributes.type == nil and #calls == 0)
combat = false
over.scripts.PreClick(over, "LeftButton", true)
assert(over.attributes.type == "macro" and #calls == 4 and saves == 1)

print("mobile add-on switch: other on, this one off, one reload; never in combat or without the other; the touch goes through a secure /reload, the add-on change saved first and checked: PASS")
