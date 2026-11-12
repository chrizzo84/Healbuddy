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

---------------------------------------------------------------------------
-- Zauberbuch
---------------------------------------------------------------------------
ns.spells = {}     -- [name] = { name, icon, ranks = { { id, label, n }, ... } }
ns.spellList = {}  -- alphabetisch sortiert

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
        -- Nur Hilfszauber; falls der Client das nicht verrät, alle aktiven Zauber
        if e.helpful or e.unknown or helpfulCount == 0 then
            e.seen = nil
            table.sort(e.ranks, function(a, b)
                if a.n and b.n and a.n ~= b.n then return a.n < b.n end
                return a.id < b.id
            end)
            for i, r in ipairs(e.ranks) do
                r.label = (r.sub and r.sub ~= "") and r.sub or ("Rang " .. i)
            end
            spells[name] = e
            table.insert(list, e)
        end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    ns.spells, ns.spellList = spells, list
end

---------------------------------------------------------------------------
-- Datenbank
---------------------------------------------------------------------------
local function Defaults()
    HealbuddyDB = HealbuddyDB or {}
    HealbuddyCharDB = HealbuddyCharDB or {}
    local db, cdb = HealbuddyDB, HealbuddyCharDB
    if db.scale == nil then db.scale = 1 end
    if db.locked == nil then db.locked = false end
    if db.fsr == nil then db.fsr = true end
    if not cdb.bindings then
        cdb.bindings = {
            [""] = { [1] = { kind = "target" }, [2] = { kind = "menu" } },
        }
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

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("SPELLS_CHANGED")
f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then Defaults() end
    elseif event == "PLAYER_LOGIN" then
        ns.Safe(ns.ScanSpells)
        ns.Safe(ns.CreateFrames)
        ns.loggedIn = true
    elseif event == "SPELLS_CHANGED" and ns.loggedIn then
        ns.Safe(ns.ScanSpells)
        if ns.RefreshOptions then ns.RefreshOptions() end
    end
end)

SLASH_HEALBUDDY1 = "/hb"
SLASH_HEALBUDDY2 = "/healbuddy"
SlashCmdList["HEALBUDDY"] = function(msg)
    msg = (msg or ""):lower()
    if msg == "lock" or msg == "unlock" then
        ns.db.locked = (msg == "lock")
        ns.UpdateLock()
        if ns.RefreshOptions then ns.RefreshOptions() end
    elseif msg == "reset" then
        ns.ResetPosition()
    else
        ns.ToggleOptions()
    end
end
