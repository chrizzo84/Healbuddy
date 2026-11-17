local _, ns = ...
local L = ns.L
local issecret = ns.issecret

-- Eigene Abklingzeiten als kleine Icons zwischen Manabalken und Frames.
-- Welche Zauber erscheinen, legt man unter /hbu -> Cooldowns fest; die
-- wichtigen Heiler-Cooldowns der Klasse sind von Haus aus an.
local SIZE, GAP = 18, 1

-- Zauber-IDs (Rang 1); angezeigt wird nur, was der Charakter beherrscht
local CURATED = {
    PRIEST = { 17, 14751, 10060, 33206, 47788, 47540, 33076, 34861, 64843, 13908, 6346, 34433, 724, 586 },
    DRUID = { 17116, 18562, 29166, 20484, 740, 48438, 22812 },
    PALADIN = { 633, 20216, 20473, 31842, 1022, 642, 498, 1044 },
    SHAMAN = { 16188, 16190, 61295, 55198, 2825, 32182, 8177 },
    MAGE = { 12051, 2139, 1953 },
}

local row, anchorFrame
local icons = {}
local curated = {}

local function BaseCooldown(id)
    if not GetSpellBaseCooldown then return nil end
    local ok, ms = pcall(GetSpellBaseCooldown, id)
    if ok and ms and not issecret(ms) then return ms / 1000 end
    return nil
end

-- Alle Zauber, die als Cooldown-Icon in Frage kommen: zuerst die Auswahl für
-- die Klasse, danach alles andere, das überhaupt eine eigene Abklingzeit hat
-- (die globale Abklingzeit zählt nicht). Verrät der Client die Abklingzeit
-- nicht, werden alle aktiven Zauber angeboten.
function ns.CooldownCandidates()
    local list, seen, extra = {}, {}, {}
    wipe(curated)
    for _, id in ipairs(CURATED[ns.class] or {}) do
        local name = ns.SpellName(id)
        local entry = name and ns.known[name]
        if entry and not seen[name] then
            seen[name], curated[name] = true, true
            table.insert(list, entry)
        end
    end
    for name, entry in pairs(ns.known) do
        if not seen[name] then
            local cd = BaseCooldown(entry.ranks[#entry.ranks].id)
            if cd == nil or cd > 0 then table.insert(extra, entry) end
        end
    end
    table.sort(extra, function(a, b) return a.name < b.name end)
    for _, entry in ipairs(extra) do table.insert(list, entry) end
    return list
end

function ns.CooldownShown(name)
    local value = ns.cdb.cooldowns[name]
    if value == nil then return curated[name] or false end
    return value
end

function ns.ToggleCooldown(name)
    ns.cdb.cooldowns[name] = not ns.CooldownShown(name)
    ns.UpdateCooldowns()
end

-- Im Kampf sind Abklingzeiten geheim; das "Duration"-Objekt darf man trotzdem
-- an die Cooldown-Anzeige durchreichen. Der zweite Parameter blendet die
-- globale Abklingzeit aus.
local function UpdateIcon(ic)
    local cd = ic.cd
    if C_Spell and C_Spell.GetSpellCooldownDuration and cd.SetCooldownFromDurationObject then
        local duration = C_Spell.GetSpellCooldownDuration(ic.id, true)
        if duration then cd:SetCooldownFromDurationObject(duration) else cd:Clear() end
        return
    end
    local info = C_Spell and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(ic.id)
    if not info then return cd:Clear() end
    if issecret(info.startTime) or issecret(info.duration) then return end
    if info.duration and info.duration > 1.5 then
        cd:SetCooldown(info.startTime, info.duration)
    else
        cd:Clear()
    end
end

local function Refresh()
    for _, ic in ipairs(icons) do
        if ic:IsShown() then ns.Safe(UpdateIcon, ic) end
    end
end

local function GetIcon(i)
    local ic = icons[i]
    if not ic then
        ic = CreateFrame("Frame", nil, row)
        ic:SetSize(SIZE, SIZE)
        local edge = ic:CreateTexture(nil, "BACKGROUND")
        edge:SetPoint("TOPLEFT", -1, 1)
        edge:SetPoint("BOTTOMRIGHT", 1, -1)
        edge:SetColorTexture(0, 0, 0, 1)
        ic.tex = ic:CreateTexture(nil, "ARTWORK")
        ic.tex:SetAllPoints()
        ic.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        ic.cd = CreateFrame("Cooldown", nil, ic, "CooldownFrameTemplate")
        ic.cd:SetAllPoints()
        ic.cd:EnableMouse(false)
        icons[i] = ic
    end
    return ic
end

function ns.UpdateCooldowns()
    if not row then return end
    local count = 0
    for _, entry in ipairs(ns.CooldownCandidates()) do
        if ns.CooldownShown(entry.name) then
            count = count + 1
            local ic = GetIcon(count)
            ic.id = entry.ranks[#entry.ranks].id
            ic.tex:SetTexture(entry.icon)
            ic:Show()
        end
    end
    for i = count + 1, #icons do icons[i]:Hide() end

    -- So viele Icons pro Zeile, wie über ein Frame passen; der Rest bricht um
    local perRow = math.max(1, math.floor((ns.db.width + GAP) / (SIZE + GAP)))
    for i = 1, count do
        local ic = icons[i]
        ic:ClearAllPoints()
        ic:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT",
            ((i - 1) % perRow) * (SIZE + GAP), math.floor((i - 1) / perRow) * (SIZE + GAP))
    end
    local lines = math.ceil(count / perRow)
    row:ClearAllPoints()
    row:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, count > 0 and 2 or 0)
    row:SetPoint("BOTTOMRIGHT", anchorFrame, "TOPRIGHT", 0, count > 0 and 2 or 0)
    row:SetHeight(count > 0 and (lines * (SIZE + GAP) - GAP) or 0.1)
    Refresh()
end

function ns.CreateCooldowns(anchor)
    anchorFrame = anchor
    row = CreateFrame("Frame", nil, anchor)
    row:SetHeight(0.1)
    ns.cdRow = row
    ns.UpdateCooldowns()

    local ev = CreateFrame("Frame")
    pcall(ev.RegisterEvent, ev, "SPELL_UPDATE_COOLDOWN")
    pcall(ev.RegisterEvent, ev, "PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", Refresh)
end
