local addonName, ns = ...

-- Maustasten und Modifikatoren, die belegt werden können
ns.BUTTONS = { "Linksklick", "Rechtsklick", "Mittelklick", "Maustaste 4", "Maustaste 5" }
ns.MODS = {
    { key = "", label = "Ohne" },
    { key = "shift-", label = "Shift" },
    { key = "ctrl-", label = "Strg" },
    { key = "alt-", label = "Alt" },
}

-- Secret Values (Midnight/Forever): Werte, mit denen man nicht rechnen/vergleichen darf
ns.issecret = issecretvalue or function() return false end
local issecret = ns.issecret

local MANA = (Enum and Enum.PowerType and Enum.PowerType.Mana) or 0
ns.MANA = MANA

local reported, reportCount = {}, 0
function ns.Report(err)
    err = tostring(err)
    if reported[err] or reportCount >= 5 then return end
    reported[err] = true
    reportCount = reportCount + 1
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ddffHealbuddy|r Fehler: " .. err, 1, 0.4, 0.4)
end

function ns.Safe(func, ...)
    local ok, err = pcall(func, ...)
    if not ok then ns.Report(err) end
end

function ns.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ddffHealbuddy|r: " .. msg)
end

-- Geschützte Aktionen (Attribute, Position, Sichtbarkeit) sind im Kampf gesperrt
local queue = {}
function ns.AfterCombat(func)
    if InCombatLockdown() then
        queue[func] = true
    else
        func()
    end
end

function ns.SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
end

-- Manakosten eines Zaubers; nil, wenn unbekannt
function ns.ManaCost(id)
    if not id or issecret(id) or not (C_Spell and C_Spell.GetSpellPowerCost) then return nil end
    local costs = C_Spell.GetSpellPowerCost(id)
    if not costs then return nil end
    for _, c in ipairs(costs) do
        if issecret(c.type) or issecret(c.cost) then return nil end
        if c.type == MANA then return c.cost end
    end
    return 0
end

---------------------------------------------------------------------------
-- Klassendaten (Zauber-IDs von Rang 1; die Namen liefert der Client)
---------------------------------------------------------------------------
-- { Modifikator, Maustaste, Kandidaten in Wunschreihenfolge }
local CLASS_DEFAULTS = {
    PRIEST = {
        { "", 1, 2061, 2054, 2050 },      -- Blitzheilung / Heilen / Geringes Heilen
        { "", 2, 2060, 2054, 2050 },      -- Große Heilung
        { "shift-", 1, 139 },             -- Erneuerung
        { "shift-", 2, 17 },              -- Machtwort: Schild
        { "ctrl-", 1, 527 },              -- Magiebannung
        { "ctrl-", 2, 552, 528 },         -- Krankheit aufheben / heilen
    },
    DRUID = {
        { "", 1, 5185 },                  -- Heilende Berührung
        { "", 2, 8936 },                  -- Nachwachsen
        { "shift-", 1, 774 },             -- Verjüngung
        { "shift-", 2, 18562 },           -- Rasche Heilung
        { "ctrl-", 1, 2782 },             -- Fluch aufheben
        { "ctrl-", 2, 2893, 8946 },       -- Vergiftung aufheben / heilen
    },
    PALADIN = {
        { "", 1, 19750, 635 },            -- Lichtblitz / Heiliges Licht
        { "", 2, 635 },                   -- Heiliges Licht
        { "ctrl-", 1, 4987, 1152 },       -- Reinigung des Glaubens / Läutern
    },
    SHAMAN = {
        { "", 1, 8004, 331 },             -- Geringe Welle der Heilung / Welle der Heilung
        { "", 2, 331 },                   -- Welle der Heilung
        { "shift-", 1, 1064 },            -- Kettenheilung
        { "ctrl-", 1, 526 },              -- Vergiftung heilen
        { "ctrl-", 2, 2870 },             -- Krankheit heilen
    },
    MAGE = {
        { "ctrl-", 1, 475 },              -- Geringen Fluch aufheben
    },
}
ns.CLASS_DEFAULTS = CLASS_DEFAULTS
local RES = { PRIEST = 2006, PALADIN = 7328, SHAMAN = 2008 }
-- Klassenbuff: Einzelbuff zuerst (wird beim Klick gewirkt), danach Gruppenversion
local CLASS_BUFF = {
    PRIEST = { 1243, 21562 },
    DRUID = { 1126, 21849 },
    MAGE = { 1459, 23028 },
}

---------------------------------------------------------------------------
-- Zauberbuch
---------------------------------------------------------------------------
ns.spells = {}     -- [name] = { name, icon, ranks = { { id, label, sub, n }, ... } }
ns.spellList = {}  -- alphabetisch sortiert
ns.known = {}      -- [name] = Eintrag, auch für Nicht-Hilfszauber

local function IsHelpful(id, name)
    if C_Spell and C_Spell.IsSpellHelpful then return C_Spell.IsSpellHelpful(id) end
    if IsHelpfulSpell then return IsHelpfulSpell(name) end
    return nil
end

local function Subtext(id, sub)
    if sub and sub ~= "" then return sub end
    if C_Spell and C_Spell.GetSpellSubtext then
        sub = C_Spell.GetSpellSubtext(id)
    elseif GetSpellSubtext then
        sub = GetSpellSubtext(id)
    end
    return sub
end

local function ScanSpellBook(add)
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
        local bank = Enum.SpellBookSpellBank.Player
        local spellType = Enum.SpellBookItemType.Spell
        for tab = 1, C_SpellBook.GetNumSpellBookSkillLines() do
            local line = C_SpellBook.GetSpellBookSkillLineInfo(tab)
            if line then
                local first = line.itemIndexOffset + 1
                for i = first, line.itemIndexOffset + line.numSpellBookItems do
                    local info = C_SpellBook.GetSpellBookItemInfo(i, bank)
                    if info and info.itemType == spellType and not info.isPassive and not info.isOffSpec then
                        add(info.name, info.spellID, info.iconID, info.subName)
                    end
                end
            end
        end
    elseif GetNumSpellTabs then
        for tab = 1, GetNumSpellTabs() do
            local _, _, offset, num = GetSpellTabInfo(tab)
            for i = offset + 1, offset + num do
                local kind, id = GetSpellBookItemInfo(i, "spell")
                local name, sub = GetSpellBookItemName(i, "spell")
                if kind == "SPELL" and id and name and not IsPassiveSpell(i, "spell") then
                    add(name, id, GetSpellTexture(id), sub)
                end
            end
        end
    end
end

local function UpdateClassData()
    local _, class = UnitClass("player")
    ns.class = class

    local res = RES[class] and ns.SpellName(RES[class])
    ns.resName = res and ns.known[res] and res or nil

    ns.classBuff = nil
    local ids = CLASS_BUFF[class]
    if ids then
        local names = {}
        for _, id in ipairs(ids) do
            local name = ns.SpellName(id)
            if name then table.insert(names, name) end
        end
        local cast = names[1]
        if cast and ns.known[cast] then
            ns.classBuff = { names = names, cast = cast, icon = ns.known[cast].icon }
        end
    end
end

function ns.ScanSpells()
    local all, helpfulCount = {}, 0
    ScanSpellBook(function(name, id, icon, sub)
        if not name or not id then return end
        local entry = all[name]
        if not entry then
            entry = { name = name, icon = icon, ranks = {}, seen = {} }
            all[name] = entry
        end
        if entry.seen[id] then return end
        entry.seen[id] = true
        if not icon and C_Spell and C_Spell.GetSpellTexture then icon = C_Spell.GetSpellTexture(id) end
        entry.icon = icon or entry.icon
        local helpful = IsHelpful(id, name)
        if helpful then entry.helpful = true end
        if helpful == nil then entry.unknown = true end
        sub = Subtext(id, sub)
        local n = sub and tonumber(sub:match("%d+"))
        table.insert(entry.ranks, { id = id, sub = sub, n = n })
    end)

    for _, e in pairs(all) do
        if e.helpful then helpfulCount = helpfulCount + 1 end
    end

    local spells, list = {}, {}
    for name, e in pairs(all) do
        e.seen = nil
        table.sort(e.ranks, function(a, b)
            if a.n and b.n and a.n ~= b.n then return a.n < b.n end
            return a.id < b.id
        end)
        for i, r in ipairs(e.ranks) do
            r.label = (r.sub and r.sub ~= "") and r.sub or ("Rang " .. i)
        end
        -- Nur Hilfszauber; falls der Client das nicht verrät, alle aktiven Zauber
        if e.helpful or e.unknown or helpfulCount == 0 then
            spells[name] = e
            table.insert(list, e)
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    ns.spells, ns.spellList, ns.known = spells, list, all
    UpdateClassData()
end

---------------------------------------------------------------------------
-- Datenbank und Belegung
---------------------------------------------------------------------------
local function Defaults()
    HealbuddyDB = HealbuddyDB or {}
    HealbuddyCharDB = HealbuddyCharDB or {}
    local db, cdb = HealbuddyDB, HealbuddyCharDB
    if db.scale == nil then db.scale = 1 end
    if db.locked == nil then db.locked = false end
    if db.fsr == nil then db.fsr = true end
    if db.context == nil then db.context = false end
    if db.pets == nil then db.pets = false end
    if db.preset == nil then db.preset = "Kompakt" end
    if db.width == nil then db.width = 88 end
    if db.height == nil then db.height = 40 end
    if db.texture == nil then db.texture = "Standard" end
    if db.colorMode == nil then db.colorMode = "class" end
    if db.percent == nil then db.percent = true end
    if db.minimapAngle == nil then db.minimapAngle = 215 end
    if not cdb.bindings then
        cdb.bindings = {}
        cdb.needSetup = true
    end
    for _, mod in ipairs(ns.MODS) do
        cdb.bindings[mod.key] = cdb.bindings[mod.key] or {}
    end
    ns.db, ns.cdb = db, cdb
end

-- Liefert das Binding (legt es bei Bedarf an)
function ns.GetBinding(mod, button)
    local t = ns.cdb.bindings[mod]
    t[button] = t[button] or { kind = "none" }
    return t[button]
end

-- Was beim Klick tatsächlich gecastet wird: Name = immer höchster Rang, ID = fester Rang
function ns.ResolveSpell(binding)
    if binding.max or not binding.id then return binding.spell end
    return binding.id
end

-- Dasselbe als Text für Makros: "Name" bzw. "Name(Rang 2)"
function ns.MacroSpell(binding)
    if not binding.max and binding.id then
        local spell = ns.known[binding.spell]
        for _, r in ipairs(spell and spell.ranks or {}) do
            if r.id == binding.id and r.sub and r.sub ~= "" then
                return binding.spell .. "(" .. r.sub .. ")"
            end
        end
    end
    return binding.spell
end

-- Sinnvolle Startbelegung für die Klasse; force = vorhandene Belegung überschreiben
function ns.AutoSetup(force)
    local cdb = ns.cdb
    if not (force or cdb.needSetup) then return end
    local def = CLASS_DEFAULTS[ns.class]
    local b, used, any = {}, {}, false
    for _, mod in ipairs(ns.MODS) do b[mod.key] = {} end

    for _, d in ipairs(def or {}) do
        for i = 3, #d do
            local name = ns.SpellName(d[i])
            if name and ns.spells[name] and not used[name] then
                b[d[1]][d[2]] = { kind = "spell", spell = name, max = true }
                used[name], any = true, true
                break
            end
        end
    end
    -- Anvisieren und Menü: auf der bloßen Taste, sonst mit Alt
    if b[""][1] then b["alt-"][1] = { kind = "target" } else b[""][1] = { kind = "target" } end
    if b[""][2] then b["alt-"][2] = { kind = "menu" } else b[""][2] = { kind = "menu" } end

    cdb.bindings = b
    -- Hat die Klasse Heilzauber, kennt sie aber noch nicht: später erneut versuchen
    cdb.needSetup = (def ~= nil and not any) or nil
    if ns.ApplyBindings then ns.ApplyBindings() end
    if any then ns.Print("Startbelegung für deine Klasse gesetzt – ansehen/ändern mit /hbu.") end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("SPELLS_CHANGED")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then Defaults() end
    elseif event == "PLAYER_LOGIN" then
        ns.Safe(ns.ScanSpells)
        ns.Safe(ns.AutoSetup)
        ns.Safe(ns.CreateFrames)
        ns.Safe(ns.CreateMinimapButton)
        ns.loggedIn = true
    elseif event == "SPELLS_CHANGED" and ns.loggedIn then
        ns.Safe(ns.ScanSpells)
        ns.Safe(ns.AutoSetup)
        ns.ApplyBindings()
        if ns.RefreshOptions then ns.RefreshOptions() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        local q = queue
        queue = {}
        for func in pairs(q) do ns.Safe(func) end
    end
end)

SLASH_HEALBUDDY1 = "/hbu"
SLASH_HEALBUDDY2 = "/healbuddy"
SlashCmdList["HEALBUDDY"] = function(msg)
    msg = (msg or ""):lower()
    if msg == "lock" or msg == "unlock" then
        ns.db.locked = (msg == "lock")
        ns.UpdateLock()
        if ns.RefreshOptions then ns.RefreshOptions() end
    elseif msg == "reset" then
        ns.ResetPosition()
    elseif msg == "test" then
        ns.Safe(ns.RunTest)
    elseif msg == "ticks" then
        ns.FSRDebug()
    else
        ns.ToggleOptions()
    end
end
