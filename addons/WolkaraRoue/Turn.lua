-- Interface mobile : les roues qui tournent.
--
-- Les sorts de chaque côté forment une grande roue centrée sur le coin bas de l'écran, celle de
-- gauche en miroir de celle de droite. On n'en voit que le quart au-dessus du stick, vers le
-- centre de l'écran ; les autres sorts attendent hors de l'écran et reviennent quand on la fait
-- tourner. Elle ne passe jamais sous le stick (à droite, c'est là qu'est le saut).
--
-- Chaque côté a quatre roues (0.8, demandé sur l'iPhone le 2026-11-09) ; on en voit une à la
-- fois. Un glissé en diagonale depuis un de ses sorts passe à la suivante : vers le centre de
-- l'écran, la suivante ; vers le coin, la précédente. Seules comptent les roues qui ont un sort
-- (toutes en personnalisant). Des points au bout de la diagonale disent laquelle on voit. Un
-- glissé est une diagonale s'il fait au moins PAGE_SWIPE unités et s'écarte de moins de 35° de
-- la diagonale : le long de la roue, là où l'on glisse pour la faire tourner, le doigt va à plus
-- de 45° de là, sur tout le quart visible.
--
-- On la fait tourner en glissant le doigt depuis un de ses sorts, le long de la roue ; toucher
-- un sort sans glisser le lance, au moment où l'on relève le doigt. Ailleurs, rien n'est capté :
-- un glissé à côté des sorts reste à la caméra. Hors combat, les sorts suivent le doigt. En
-- combat, le jeu ne laisse bouger ses boutons que par son code sécurisé, qui ne voit que l'appui
-- et le relâchement : la roue tourne alors d'autant de crans, ou passe à la suivante, au moment
-- où l'on relève le doigt. Ce code sécurisé ne fait que de l'arithmétique et lit des positions
-- calculées d'avance. Il ne suit que le bouton gauche : l'appui long, que l'app donne en clic
-- droit, et le glissé du bouton droit qui le suit sont à Free.lua (déplacer un sort).
--
-- La roue de gauche se calcule comme celle de droite vue dans un miroir : mêmes angles, mêmes
-- crans, positions retournées de gauche à droite. Rien ne dessine les roues : ni disque ni
-- ombre, seuls leurs sorts (et les points des roues) sont à l'écran.
--
-- Le code sécurisé est accroché à chaque sort par le gabarit de l'appui et du relâchement
-- (attributs _onmousedown et _onmouseup) : le jeu refuse d'envelopper ces deux moments
-- (« Unsupported script type 'OnMouseDown' », 2026-11-09). Hors combat, l'addon calcule aussi
-- le relâchement lui-même, comme le ferait le code sécurisé.
--
-- Un glissé finit toujours. Un glissé du bouton gauche n'est jamais un glisser-déposer du jeu,
-- qui peut ne jamais rendre au sort le relâchement du doigt (la roue suivait alors le curseur
-- après coup, et les deux roues tournaient ensemble, 2026-11-07). Hors combat, un glissé dont le
-- doigt s'est relevé sans que le jeu le dise se termine quand même, et en commencer un sur une
-- roue arrête les autres.

local _, ns = ...

local Turn = ns.Register("Roues tournantes", {})
ns.Turn = Turn

local SIZE = 64         -- un sort, comme les boutons libres
local FIRST = 95        -- le premier emplacement, en degrés depuis le bord (sens direct, vu de droite)
local SWIPE = 0.35      -- en crans : en deçà, le doigt a touché le sort ; au-delà, il a glissé
local PAGE_SWIPE = 40   -- en unités : la longueur d'un glissé en diagonale qui change de roue
local DIAGONAL = 2      -- (le long)² ≥ 2 (en travers)² : à moins de 35° de la diagonale
local REACH = 3         -- la bande dépasse la roue de trois sorts : un glissé qui finit au-delà se lit
local DOT, DOT_GAP = 10, 16
Turn.SWIPE, Turn.PAGE_SWIPE = SWIPE, PAGE_SWIPE

local SIDES = {
    right = { key = "free", name = "WolkaraMobileTurn", corner = "BOTTOMRIGHT", mirror = false },
    left = { key = "freeLeft", name = "WolkaraMobileTurnLeft", corner = "BOTTOMLEFT", mirror = true },
}
local ORDER = { "right", "left" }
local sides, attached = {}, {}

local function PageSettings(wheel) return ns.PageData(ns.db[wheel.key], wheel.page) end

-- Toujours vrai depuis la 0.8 (le mode « Arc » est parti) ; gardé pour qui le demande.
function Turn:Enabled() return true end

-- La roue est centrée sur le coin bas ; son rayon passe au-dessus du stick.
-- Les sorts s'y suivent serrés : d'un centre au suivant, 1,25 taille de sort à « Écart des
-- sorts » 100 %, de 1,11 (presque bord à bord) à 60 % jusqu'à 1,53 à 180 %.
function Turn.Geometry(width, height, count, spread)
    local stick = math.sqrt((width * ns.STICK_X) ^ 2 + (height * ns.STICK_Y) ^ 2)
    local radius = stick + height * 0.15
    local apart = SIZE * (0.9 + 0.35 * (spread or 100) / 100)
    local step = math.deg(2 * math.asin(math.min(1, apart / (2 * radius))))
    return radius, step
end

-- L'emplacement d'un sort (1 à count) pour un décalage donné, fractionnaire pendant un glissé.
-- L'angle se lit vu de droite ; à gauche, le miroir le retourne.
function Turn.Angle(index, offset, count, step)
    return FIRST + ((index - 1 + offset) % count) * step
end

-- Un glissé de (dx, dy), dx compté du coin vers l'intérieur de l'écran (retourné à gauche), dy
-- vers le haut : 1 en diagonale vers le centre de l'écran (la roue suivante), -1 vers le coin
-- (la précédente), 0 sinon.
function Turn.Diagonal(dx, dy)
    if dx * dx + dy * dy < PAGE_SWIPE * PAGE_SWIPE then return 0 end
    local along, across = dx + dy, dx - dy
    if along * along < DIAGONAL * across * across then return 0 end
    return along > 0 and 1 or -1
end

local function Point(wheel, radius, degrees)
    local angle = math.rad(degrees)
    local x, y = radius * math.cos(angle), radius * math.sin(angle)
    if wheel.mirror then x = -x end
    return x, y
end

-- Les boutons ont la taille des boutons libres : un décalage se compte à leur échelle.
local function Place(wheel, offset)
    local band, buttons = wheel.band, wheel.buttons
    if not buttons or InCombatLockdown() or not band.radius then return end
    local count = band:GetAttribute("count") or 0
    local radius, step, scale = band.radius, band:GetAttribute("step"), band.buttonScale or 1
    for index = 1, count do
        local x, y = Point(wheel, radius, Turn.Angle(index, offset, count, step))
        buttons[index]:ClearAllPoints()
        buttons[index]:SetPoint("CENTER", band, wheel.corner, x / scale, y / scale)
    end
end

-- Le doigt vu du coin de la roue, hors code sécurisé : vers l'intérieur de l'écran, et en haut.
local function CursorPoint(wheel)
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    x, y = x / scale, y / scale
    return wheel.mirror and x or UIParent:GetWidth() - x, y
end
local function AngleOf(px, py) return math.deg(math.atan2(py, -px)) end

-- ---------------------------------------------------------------------------------------
-- Les quatre roues d'un côté

-- La roue suivante dans un sens (1 ou -1), parmi celles qu'on peut montrer ; nil sinon.
function Turn.NextPage(side, direction)
    local state = sides[side]
    if not state then return nil end
    local page = state.pager:GetAttribute("page") or 1
    local target = page
    for _ = 1, ns.PAGES - 1 do
        target = (target - 1 + direction) % ns.PAGES + 1
        if state.pager:GetAttribute("use" .. target) then return target end
    end
    return nil
end

-- Hors combat : montre la roue `page` d'un côté, cache les autres.
function Turn.ShowPage(side, page)
    local state = sides[side]
    if not state or InCombatLockdown() then return end
    for index, wheel in ipairs(state.wheels) do wheel.band:SetShown(index == page) end
    state.pager:SetAttribute("page", page)
    if ns.db then ns.db[state.key].page = page end
end

function Turn.Step(side, direction)
    local target = Turn.NextPage(side, direction)
    if target then Turn.ShowPage(side, target) end
    return target
end

function Turn.CurrentPage(side)
    local state = sides[side]
    return state and state.pager:GetAttribute("page") or 1
end

-- Les points des roues, sur la diagonale juste au-delà des sorts, en travers d'elle : un par roue
-- qu'on peut montrer, doré pour celle-ci. Rien quand il n'y en a qu'une.
local function LayoutDots(wheel, usable, radius)
    local dots, list = wheel.band.dots, {}
    for page = 1, ns.PAGES do if usable[page] then list[#list + 1] = page end end
    local degrees = FIRST + (180 - FIRST) / 2
    local cx, cy = Point(wheel, radius + SIZE * 0.95, degrees)
    local tx, ty = -math.sin(math.rad(degrees)), math.cos(math.rad(degrees))
    if wheel.mirror then tx = -tx end
    for i, dot in ipairs(dots) do
        local page = list[i]
        if #list > 1 and page then
            local k = i - (#list + 1) / 2
            dot:ClearAllPoints()
            dot:SetPoint("CENTER", wheel.band, wheel.corner, cx + k * DOT_GAP * tx, cy + k * DOT_GAP * ty)
            if page == wheel.page then dot:SetVertexColor(1, 0.82, 0.3, 1) else dot:SetVertexColor(0.8, 0.8, 0.8, 0.55) end
            dot:Show()
        else
            dot:Hide()
        end
    end
end

local function MakeDots(band)
    local dots = {}
    for i = 1, ns.PAGES do
        local dot = band:CreateTexture(nil, "OVERLAY")
        dot:SetTexture(ns.WHITE)
        dot:SetSize(DOT, DOT)
        ns.Circle(band, dot)
        dot:Hide()
        dots[i] = dot
    end
    return dots
end

-- ---------------------------------------------------------------------------------------
-- Hors combat : le doigt suivi par l'addon

-- Un glissé laissé ouvert s'arrête, la roue revient au cran retenu.
local function Drop(wheel)
    wheel.dragging = false
    Place(wheel, wheel.band:GetAttribute("offset") or 0)
end

-- Le doigt s'est relevé (dit au sort, ou vu par l'addon). Une diagonale passe à une autre roue
-- (le code sécurisé l'a normalement déjà fait) ; sinon le glissé se finit comme le code
-- sécurisé l'aurait fait : au cran le plus proche, retenu pour le prochain lancement. Vrai si le
-- doigt a glissé.
local function Release(wheel)
    local band, state = wheel.band, wheel.state
    wheel.dragging = false
    local px, py = CursorPoint(wheel)
    local direction = Turn.Diagonal(px - wheel.fromX, py - wheel.fromY)
    if direction ~= 0 then
        Place(wheel, wheel.dragOffset or 0)
        if state.pager:GetAttribute("page") == wheel.page then
            Turn.Step(wheel.side, direction)
        elseif ns.db then
            ns.db[wheel.key].page = state.pager:GetAttribute("page")
        end
        return true
    end
    local count = band:GetAttribute("count") or 0
    local turns = (AngleOf(px, py) - wheel.dragFrom) / (band:GetAttribute("step") or 20)
    local offset = wheel.dragOffset or 0
    local swiped = turns >= SWIPE or turns <= -SWIPE
    if count > 0 and swiped then
        offset = (offset + math.floor(turns + 0.5)) % count
    end
    band:SetAttribute("offset", offset)
    Place(wheel, offset)
    PageSettings(wheel).turnOffset = offset
    return swiped
end

local function Follow(wheel)
    if not wheel.dragging or InCombatLockdown() then return end
    -- Le doigt relevé, d'après le jeu : cru seulement s'il l'a d'abord vu posé pendant ce
    -- glissé (l'état des boutons passe par la traduction de l'app, qu'on ne suppose pas).
    if IsMouseButtonDown then
        if IsMouseButtonDown("LeftButton") then
            wheel.held = true
        elseif wheel.held then
            Release(wheel)
            return
        end
    end
    local px, py = CursorPoint(wheel)
    -- En route pour une autre roue : celle-ci ne tourne pas.
    if Turn.Diagonal(px - wheel.fromX, py - wheel.fromY) ~= 0 then
        Place(wheel, wheel.dragOffset)
        return
    end
    local turns = (AngleOf(px, py) - wheel.dragFrom) / (wheel.band:GetAttribute("step") or 20)
    if turns < SWIPE and turns > -SWIPE then turns = 0 end
    Place(wheel, wheel.dragOffset + turns)
end

local function Pressed(wheel, button, mouse)
    if mouse and mouse ~= "LeftButton" then return end
    button.swiped = nil
    if InCombatLockdown() then return end
    -- Un seul doigt tourne une roue : les autres, si elles suivaient encore, s'arrêtent.
    for _, state in pairs(sides) do
        for _, other in ipairs(state.wheels) do
            if other ~= wheel and other.dragging then Drop(other) end
        end
    end
    local px, py = CursorPoint(wheel)
    wheel.dragging, wheel.held = true, false
    wheel.fromX, wheel.fromY, wheel.dragFrom = px, py, AngleOf(px, py)
    wheel.dragOffset = wheel.band:GetAttribute("offset") or 0
end

local function Lifted(wheel, button, mouse)
    if mouse and mouse ~= "LeftButton" then return end
    if not wheel.dragging then return end
    wheel.dragging = false
    if InCombatLockdown() then return end
    -- Un glissé ne doit pas non plus ouvrir le sélecteur d'une case vide (PostClick).
    if Release(wheel) then button.swiped = true end
end

-- ---------------------------------------------------------------------------------------
-- Le code sécurisé

-- La position du doigt sur la bande, vue de son coin : px vers l'intérieur de l'écran (retourné
-- à gauche), py vers le haut ; et son angle, entre 90 et 180 degrés, par une approximation de
-- l'arc tangente juste à un tiers de degré près (le code sécurisé n'a que l'arithmétique). Ces
-- extraits sont accrochés à chaque sort : self est le sort, owner la bande de sa roue.
local POSITION = [=[
    local mx, my = owner:GetMousePosition()
    local px, py, angle
    if mx then
        local size = owner:GetAttribute("size")
        px, py = mx * size, my * size
        if not owner:GetAttribute("mirror") then px = size - px end
        if px <= 0 then angle = 90
        else
            local t = py / px
            local inverse = t > 1
            if inverse then t = 1 / t end
            local a = 45 * t + 15.64 * t * (1 - t)
            if inverse then a = 90 - a end
            angle = 180 - a
        end
    end
]=]

-- Le glissé depuis l'appui (fx, fy) : 1 ou -1 en diagonale (Turn.Diagonal), 0 sinon.
local DIAGONAL_CODE = [=[
    local diagonal = 0
    if px and fx then
        local dx, dy = px - fx, py - fy
        if dx * dx + dy * dy >= ]=] .. PAGE_SWIPE * PAGE_SWIPE .. [=[ then
            local along, across = dx + dy, dx - dy
            if along * along >= ]=] .. DIAGONAL .. [=[ * across * across then
                if along > 0 then diagonal = 1 else diagonal = -1 end
            end
        end
    end
]=]

-- Le bouton de la souris : « button », dans le gabarit de l'appui et du relâchement. S'il ne
-- venait pas, tout serait pris pour le bouton gauche, comme avant la 0.8.
local DOWN = [=[
    if button and button ~= "LeftButton" then return end
    owner:SetAttribute("swiped", nil)
]=] .. POSITION .. [=[
    owner:SetAttribute("downangle", angle)
    owner:SetAttribute("downx", px)
    owner:SetAttribute("downy", py)
]=]

local UP = [=[
    if button and button ~= "LeftButton" then return end
]=] .. POSITION .. [=[
    local from, fx, fy = owner:GetAttribute("downangle"), owner:GetAttribute("downx"), owner:GetAttribute("downy")
    owner:SetAttribute("downangle", nil)
    local count = owner:GetAttribute("count")
    if not angle or not from or not count or count < 1 then return end
]=] .. DIAGONAL_CODE .. [=[
    if diagonal ~= 0 then
        owner:SetAttribute("swiped", true)
        local pager = owner:GetFrameRef("pager")
        local page, pages = pager:GetAttribute("page"), pager:GetAttribute("pages")
        local target = page
        for i = 1, pages - 1 do
            target = (target - 1 + diagonal) % pages + 1
            if pager:GetAttribute("use" .. target) then break end
        end
        if target ~= page and pager:GetAttribute("use" .. target) then
            for i = 1, pages do
                local band = pager:GetFrameRef("band" .. i)
                if i == target then band:Show() else band:Hide() end
            end
            pager:SetAttribute("page", target)
        end
        return
    end
    local turns = (angle - from) / owner:GetAttribute("step")
    if turns < ]=] .. SWIPE .. [=[ and turns > -]=] .. SWIPE .. [=[ then return end
    owner:SetAttribute("swiped", true)
    turns = turns + 0.5
    turns = turns - turns % 1
    local offset = (owner:GetAttribute("offset") + turns) % count
    owner:SetAttribute("offset", offset)
    local corner = owner:GetAttribute("corner")
    for index = 1, count do
        local slot = (index - 1 + offset) % count
        local spell = owner:GetFrameRef("b" .. index)
        spell:ClearAllPoints()
        spell:SetPoint("CENTER", owner, corner, owner:GetAttribute("x" .. slot), owner:GetAttribute("y" .. slot))
    end
]=]

-- Accrochés au sort lui-même (gabarit de l'appui et du relâchement) : self est le sort, la
-- bande se retrouve par sa référence.
local PRESS = [=[
    local owner = self:GetFrameRef("wheel")
    if not owner then return end
]=] .. DOWN
local LIFT = [=[
    local owner = self:GetFrameRef("wheel")
    if not owner then return end
]=] .. UP

-- Un glissé a tourné la roue ou changé de roue : le sort sous le doigt n'est pas lancé. Si le
-- jeu passe le clic avant le relâchement, le glissé se mesure ici aussi.
local CLICK = [=[
    if button and button ~= "LeftButton" then return end
    if owner:GetAttribute("swiped") then
        owner:SetAttribute("swiped", nil)
        return false
    end
    local from, fx, fy = owner:GetAttribute("downangle"), owner:GetAttribute("downx"), owner:GetAttribute("downy")
    if down or not from then return end
]=] .. POSITION .. [=[
    if not angle then return end
]=] .. DIAGONAL_CODE .. [=[
    if diagonal ~= 0 then return false end
    local turns = (angle - from) / owner:GetAttribute("step")
    if turns >= ]=] .. SWIPE .. [=[ or turns <= -]=] .. SWIPE .. [=[ then return false end
]=]

-- ---------------------------------------------------------------------------------------

function Turn:Init()
    for _, side in ipairs(ORDER) do
        local info = SIDES[side]
        -- Ce qui sait quelle roue on voit, et lesquelles on peut montrer (attributs page, pages,
        -- use1 à use4), pour le code sécurisé.
        local pager = CreateFrame("Frame", info.name .. "Pages", UIParent, "SecureHandlerBaseTemplate")
        pager:SetAttribute("pages", ns.PAGES)
        pager:SetAttribute("page", 1)
        local state = { side = side, key = info.key, pager = pager, wheels = {} }
        for page = 1, ns.PAGES do
            -- Une bande par roue : un carré invisible sur le coin, qui ne prend aucun toucher ; les
            -- sorts de la roue sont ses enfants, si bien que la cacher cache la roue.
            local band = CreateFrame("Frame", page == 1 and info.name or (info.name .. page), UIParent,
                "SecureHandlerBaseTemplate")
            band:SetFrameStrata("LOW")
            band:SetPoint(info.corner, UIParent, info.corner)
            band:EnableMouse(false)
            band:Hide()
            band:SetAttribute("page", page)
            band:SetFrameRef("pager", pager)
            pager:SetFrameRef("band" .. page, band)
            local wheel = { side = side, key = info.key, page = page, corner = info.corner,
                mirror = info.mirror, band = band, state = state }
            band:SetScript("OnUpdate", function() Follow(wheel) end)
            band.dots = MakeDots(band)
            state.wheels[page] = wheel
        end
        sides[side] = state
    end
end

-- Free nous confie ses boutons, une liste par roue, une fois créés (avant notre Init : il passe
-- avant nous).
function Turn:Attach(pages, side) attached[side or "right"] = pages end

-- Une fois, hors combat : chaque sort rejoint la bande de sa roue, avec le code sécurisé et le
-- suivi du doigt.
local function Wrap(state)
    local pages = attached[state.side]
    if state.wrapped or not pages or InCombatLockdown() then return end
    state.wrapped = true
    for page, wheel in ipairs(state.wheels) do
        local band, buttons = wheel.band, pages[page] or {}
        wheel.buttons = buttons
        for _, button in ipairs(buttons) do
            button:SetParent(band)
            button:SetFrameStrata("LOW")
            if button.securePressRelease ~= false then
                button:SetFrameRef("wheel", band)
                button:SetAttribute("_onmousedown", PRESS)
                button:SetAttribute("_onmouseup", LIFT)
            end
            SecureHandlerWrapScript(button, "OnClick", band, CLICK)
            button:HookScript("OnMouseDown", function(_, mouse) Pressed(wheel, button, mouse) end)
            button:HookScript("OnMouseUp", function(_, mouse) Lifted(wheel, button, mouse) end)
        end
    end
end

-- Hors combat : la géométrie, les positions d'avance pour le code sécurisé, les roues qu'on peut
-- montrer, celle qu'on voit, puis les sorts.
local function LayoutSide(state)
    if InCombatLockdown() or not ns.db then return end
    Wrap(state)
    if not state.wrapped then return end
    local settings = ns.db[state.key]
    -- La roue qu'on voit et le cran de chacune sont d'abord ceux de l'écran : en combat, seul le
    -- code sécurisé les change, et le jeu peut refaire la disposition à la fin du combat avant
    -- que PLAYER_REGEN_ENABLED ne les ait retenus ; repartir de la sauvegarde ramenait alors la
    -- roue à son ancien cran.
    if state.laidOut then
        settings.page = state.pager:GetAttribute("page") or settings.page
        for _, wheel in ipairs(state.wheels) do
            local live = wheel.band:GetAttribute("offset")
            if live then PageSettings(wheel).turnOffset = live end
        end
    end
    state.laidOut = true
    local count = math.max(0, math.min(tonumber(settings.count) or 0, ns.MAX_FREE))
    local usable, first = {}, nil
    for page = 1, ns.PAGES do
        usable[page] = ns.editing == true or ns.PageHasEntries(settings, page, count)
        state.pager:SetAttribute("use" .. page, usable[page])
        if usable[page] and not first then first = page end
    end
    local current = math.max(1, math.min(ns.PAGES, math.floor(tonumber(settings.page) or 1)))
    if not usable[current] then current = first or 1 end
    settings.page = current
    state.pager:SetAttribute("page", current)
    local radius, step = Turn.Geometry(UIParent:GetWidth(), UIParent:GetHeight(), count, settings.spread)
    local size = radius + SIZE * REACH
    for page, wheel in ipairs(state.wheels) do
        local band, buttons = wheel.band, wheel.buttons
        -- Un sort de la roue part au relâchement du doigt, pour qu'un glissé puisse l'annuler. Il
        -- ne se glisse-dépose qu'au bouton droit (après un appui long, pour le déplacer).
        for _, button in ipairs(buttons) do
            button:SetAttribute("useOnKeyDown", false)
            pcall(button.RegisterForDrag, button, "RightButton")
        end
        local n = math.min(count, #buttons)
        band.radius = radius
        band.buttonScale = (settings.scale or 100) / 100
        band:SetSize(size, size)
        band:SetAttribute("size", size)
        band:SetAttribute("mirror", wheel.mirror)
        band:SetAttribute("corner", wheel.corner)
        band:SetAttribute("count", n)
        band:SetAttribute("step", step)
        local offset = n > 0 and math.floor(tonumber(PageSettings(wheel).turnOffset) or 0) % n or 0
        band:SetAttribute("offset", offset)
        for slot = 0, math.max(0, n - 1) do
            local x, y = Point(wheel, radius, FIRST + slot * step)
            band:SetAttribute("x" .. slot, x / band.buttonScale)
            band:SetAttribute("y" .. slot, y / band.buttonScale)
        end
        for index = 1, n do band:SetFrameRef("b" .. index, buttons[index]) end
        band:SetShown(page == current)
        Place(wheel, offset)
        LayoutDots(wheel, usable, radius)
    end
end

function Turn:Layout()
    for _, side in ipairs(ORDER) do
        if sides[side] then LayoutSide(sides[side]) end
    end
end

-- Le combat fini, la roue qu'on voit et le cran où chacune s'est arrêtée sont retenus.
ns.On("PLAYER_REGEN_ENABLED", function()
    if not ns.db then return end
    for _, side in ipairs(ORDER) do
        local state = sides[side]
        if state and state.wrapped then
            ns.db[state.key].page = state.pager:GetAttribute("page") or ns.db[state.key].page
            for _, wheel in ipairs(state.wheels) do
                PageSettings(wheel).turnOffset = wheel.band:GetAttribute("offset") or 0
            end
        end
    end
end)
