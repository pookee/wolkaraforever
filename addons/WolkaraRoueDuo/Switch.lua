-- Deux interfaces mobiles côte à côte, une seule active : celle-ci (WolkaraRoue, pookee) et
-- l'interface Duo de scarrdi94 (WolkaraRoueDuo, PR jklock/wolkaraforever#26). Basculer active
-- l'autre pour ce personnage, désactive celle-ci et recharge l'interface. Chacune garde ses
-- propres réglages : le jeu range les SavedVariables d'un add-on sous le nom de son dossier.
-- La disposition tactile de l'app se bascule à part (engrenage > Interface Duo).
--
-- Le rechargement passe par la commande /reload du jeu, lancée par un bouton sécurisé : le jeu
-- ne recharge l'interface pour un add-on que sur un vrai toucher, et la première tuile, qui
-- appelait ReloadUI elle-même, ne faisait rien sur l'iPhone (2026-11-09).
--
-- Le jeu oublie au rechargement un changement d'add-ons qu'on n'a pas enregistré : sa propre
-- liste d'add-ons appelle SaveAddOns avant de recharger, et la tuile, qui ne le faisait pas,
-- rechargeait sans rien changer (2026-11-09 : AddOns.txt intact, WolkaraRoueDuo jamais chargé).
-- Chaque bascule est aussi notée dans les réglages (switchLog), pour pouvoir la relire.
--
-- Le même fichier est dans les deux add-ons ; il ne dépend que du nom de son dossier.

local ADDON_NAME, ns = ...
local OTHER = ADDON_NAME == "WolkaraRoueDuo" and "WolkaraRoue" or "WolkaraRoueDuo"
ns.OTHER_INTERFACE = OTHER
ns.OTHER_INTERFACE_LABEL = OTHER == "WolkaraRoueDuo" and "Interface Duo" or "Interface pookee"
-- Jamais en combat : /stopmacro arrête la macro avant le rechargement.
ns.RELOAD_MACRO = "/stopmacro [combat]\n/reload"

local function AddOnCall(name, ...)
    local fn = (C_AddOns and C_AddOns[name]) or _G[name]
    if not fn then return false end
    return pcall(fn, ...)
end

function ns.OtherInterfaceInstalled()
    local ok, name, _, _, _, reason = AddOnCall("GetAddOnInfo", OTHER)
    return ok and name ~= nil and reason ~= "MISSING"
end

-- L'autre activée, celle-ci désactivée, pour ce personnage : vrai quand c'est fait, et le
-- prochain rechargement bascule. quiet : ne rien dire (le même toucher passe deux fois).
function ns.PrepareSwitch(quiet)
    if InCombatLockdown() then
        if not quiet then ns.Print("on change d'interface hors combat.") end
        return false
    end
    if not ns.OtherInterfaceInstalled() then
        if not quiet then ns.Print(OTHER .. " n'est pas installée sur cet appareil.") end
        return false
    end
    local character = UnitName("player")
    -- Pour ce personnage et pour tous : la liste du jeu garde l'un ou l'autre selon son réglage.
    AddOnCall("EnableAddOn", OTHER, character)
    AddOnCall("EnableAddOn", OTHER)
    AddOnCall("DisableAddOn", ADDON_NAME, character)
    AddOnCall("DisableAddOn", ADDON_NAME)
    local saved = AddOnCall("SaveAddOns")
    local state = ns.EnableState(OTHER, character)
    if ns.db then
        ns.db.switchLog = { to = OTHER, saved = saved, state = state, at = time and time() or nil }
    end
    -- Le jeu dit que l'autre reste désactivée : ne pas recharger pour rien.
    if state == 0 then
        if not quiet then ns.Print("le jeu n'a pas accepté la bascule vers " .. OTHER .. ".") end
        return false
    end
    return true
end

-- 0 désactivée, 1 pour certains personnages, 2 pour tous ; nil si le jeu ne sait pas le dire.
-- C_AddOns prend (nom, personnage) ; l'ancienne fonction globale, (personnage, nom).
function ns.EnableState(name, character)
    local ok, state
    if C_AddOns and C_AddOns.GetAddOnEnableState then
        ok, state = pcall(C_AddOns.GetAddOnEnableState, name, character)
    elseif _G.GetAddOnEnableState then
        ok, state = pcall(_G.GetAddOnEnableState, character, name)
    end
    if ok and type(state) == "number" then return state end
    return nil
end

-- /wolkaraui, tapé au clavier : un vrai appui, le rechargement direct peut passer.
function ns.SwitchInterface()
    if not ns.PrepareSwitch() then return false end
    ns.Print("bascule vers " .. ns.OTHER_INTERFACE_LABEL .. " : l'interface se recharge (sinon tape /reload).")
    ReloadUI()
    return true
end

-- Un bouton sécurisé transparent posé sur `button` : son toucher prépare la bascule, puis lance
-- le /reload du jeu. Hors combat seulement ; s'il n'y a rien à basculer, il ne recharge pas.
function ns.SwitchOnPreClick(secure, down)
    if InCombatLockdown() then return end
    secure:SetAttribute("type", ns.PrepareSwitch(not down) and "macro" or nil)
end

function ns.SecureSwitchOver(button)
    local over = CreateFrame("Button", nil, button, "SecureActionButtonTemplate")
    over:SetAllPoints(button)
    over:SetFrameLevel(button:GetFrameLevel() + 5)
    over:RegisterForClicks("AnyUp", "AnyDown")
    over:SetAttribute("type", "macro")
    over:SetAttribute("macrotext", ns.RELOAD_MACRO)
    over:SetScript("PreClick", function(self, _, down) ns.SwitchOnPreClick(self, down) end)
    return over
end

SLASH_WOLKARAUI1 = "/wolkaraui"
SlashCmdList.WOLKARAUI = function() ns.SwitchInterface() end
